import AppKit
import ScreenCaptureKit
import Darwin

/// Captures only the identified status windows, once per refresh. Images stay in memory.
enum NativeIconCapture {
    static var permitted: Bool { CGPreflightScreenCaptureAccess() }
    @MainActor private(set) static var diagnostic = "尚未读取"

    // Compatibility with status windows omitted from ScreenCaptureKit's shareable list.
    // This deprecated public capture API still requires the same TCC permission.
    private static let graphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private typealias WindowArrayImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
    private static func arrayImage(_ id: CGWindowID) -> CGImage? {
        guard permitted, ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27,
              let graphics, let address = dlsym(graphics, "CGWindowListCreateImageFromArray") else { return nil }
        var pointer = UnsafeRawPointer(bitPattern: UInt(id))
        guard let windows = CFArrayCreate(nil, &pointer, 1, nil) else { return nil }
        let capture = unsafeBitCast(address, to: WindowArrayImage.self)
        return capture(.null, windows, CGWindowImageOption.boundsIgnoreFraming.union(.bestResolution).rawValue)?.takeRetainedValue()
    }
    private typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static func statusImage(_ id: CGWindowID) -> CGImage? {
        guard permitted, ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27,
              let graphics, let address = dlsym(graphics, "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(address, to: WindowImage.self)
        return capture(.null, CGWindowListOption.optionIncludingWindow.rawValue, id,
            CGWindowImageOption.boundsIgnoreFraming.union(.bestResolution).rawValue)?.takeRetainedValue()
    }

    @MainActor static func capture(_ entries: [MenuEntry],
        onUpdate: ([String: NSImage]) -> Void) async -> [String: NSImage] {
        guard permitted else { return [:] }
        var result: [String: NSImage] = [:]
        let inventory = Dictionary(uniqueKeysWithValues: NativeStatusWindow.all().map { ($0.id, $0) })
        var matched = 0
        var emptyImages = 0
        var unavailableImages = 0
        for entry in entries {
            guard !Task.isCancelled else { return result }
            guard let id = entry.windowID, let status = inventory[id], status.pid == (entry.windowPID ?? entry.pid) else { continue }
            matched += 1
            for capture in [arrayImage, MenuWindowBridge.image, statusImage] {
                guard let image = capture(id) else { unavailableImages += 1; continue }
                guard hasVisiblePixels(image) else { emptyImages += 1; continue }
                result[entry.id] = NSImage(cgImage: image, size: status.frame.size)
                break
            }
        }
        diagnostic = "原生窗口 \(inventory.count) 个，匹配 \(matched) / \(entries.count)，直接读取 \(result.count) 个。\n空白帧 \(emptyImages) 次，未返回图像 \(unavailableImages) 次。"
        // Publish readable originals immediately; an unavailable fallback window
        // must not hold every successfully captured icon behind an async request.
        onUpdate(result)
        // macOS 26's SCK fallback cannot reliably supply these hosted status
        // surfaces; avoid repeated capture requests when the window APIs fail.
        guard #available(macOS 14.0, *), ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26,
              result.count < entries.count else { return result }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        catch { diagnostic += "\n窗口列表：\(error.localizedDescription)"; return result }
        let windows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        for entry in entries {
            guard !Task.isCancelled else { return result }
            guard result[entry.id] == nil, let id = entry.windowID, let window = windows[id], window.isOnScreen,
                  window.owningApplication?.processID == (entry.windowPID ?? entry.pid),
                  let frame = inventory[id]?.frame, frame.width > 1, frame.width < 800, frame.height > 1, frame.height < 90 else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(1, Int((frame.width * scale).rounded()))
            configuration.height = max(1, Int((frame.height * scale).rounded()))
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            let image: CGImage
            do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
            catch { diagnostic += "\n\(entry.name)：\(error.localizedDescription)"; continue }
            guard hasVisiblePixels(image) else { continue }
            result[entry.id] = NSImage(cgImage: image, size: frame.size)
            onUpdate([entry.id: result[entry.id]!])
        }
        diagnostic += "\n本轮有效原图 \(result.count) 个。"
        return result
    }

    /// Off-screen status surfaces may temporarily return a fully transparent frame.
    /// Don't replace the last readable original icon in AppModel with that frame.
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= 6400, height <= 720 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.flush()
            return stride(from: 3, to: buffer.count, by: 4).contains { buffer[$0] > 8 }
        }
    }
}
