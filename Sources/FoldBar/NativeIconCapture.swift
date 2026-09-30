import AppKit
import ScreenCaptureKit
import Darwin

/// Captures only the identified status windows, once per refresh. Images stay in memory.
enum NativeIconCapture {
    static var permitted: Bool { CGPreflightScreenCaptureAccess() }

    // Compatibility with status windows omitted from ScreenCaptureKit's shareable list.
    // This deprecated public capture API still requires the same TCC permission.
    private static let graphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static func statusImage(_ id: CGWindowID) -> CGImage? {
        guard permitted, ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27,
              let graphics, let address = dlsym(graphics, "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(address, to: WindowImage.self)
        return capture(.null, CGWindowListOption.optionIncludingWindow.rawValue, id,
            CGWindowImageOption.boundsIgnoreFraming.union(.bestResolution).rawValue)?.takeRetainedValue()
    }

    @MainActor static func capture(_ entries: [MenuEntry]) async -> [String: NSImage] {
        guard permitted else { return [:] }
        var result: [String: NSImage] = [:]
        let inventory = Dictionary(uniqueKeysWithValues: NativeStatusWindow.all().map { ($0.id, $0) })
        for entry in entries {
            guard let id = entry.windowID, let status = inventory[id], status.pid == (entry.windowPID ?? entry.pid),
                  let image = MenuWindowBridge.image(id) ?? statusImage(id) else { continue }
            result[entry.id] = NSImage(cgImage: image, size: status.frame.size)
        }
        guard #available(macOS 14.0, *), result.count < entries.count,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return result }
        let windows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
        for entry in entries {
            guard !Task.isCancelled else { return result }
            guard result[entry.id] == nil, let id = entry.windowID, let window = windows[id],
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
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { continue }
            result[entry.id] = NSImage(cgImage: image, size: frame.size)
        }
        return result
    }
}
