import AppKit
import Darwin

/// Optional WindowServer compatibility adapter. These symbols are undocumented;
/// do not assume availability on future macOS releases, and never bypass TCC.
/// ABI references are recorded in README; no third-party implementation is included.
enum MenuWindowBridge {
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private typealias Connection = @convention(c) () -> Int32
    private typealias List = @convention(c) (Int32, Int32, Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias Capture = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32, UInt32) -> Unmanaged<CFArray>?
    private typealias Bounds = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32

    private static func symbol<T>(_ name: String, as: T.Type) -> T? {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27,
              let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }

    static func descriptions() -> [[String: Any]]? {
        guard let connection = symbol("CGSMainConnectionID", as: Connection.self),
              let query = symbol("CGSGetProcessMenuBarWindowList", as: List.self) else { return nil }
        var ids = [UInt32](repeating: 0, count: 1024)
        var count: Int32 = 0
        let result = ids.withUnsafeMutableBufferPointer { buffer in
            query(connection(), 0, Int32(buffer.count), buffer.baseAddress!, &count)
        }
        guard result == 0, count >= 0, count < ids.count else { return nil }
        var pointers = ids.prefix(Int(count)).map { UnsafeRawPointer(bitPattern: Int($0)) }
        let array = pointers.withUnsafeMutableBufferPointer { buffer in
            CFArrayCreate(nil, buffer.baseAddress, buffer.count, nil)
        }
        guard let array else { return nil }
        return CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
    }

    /// Restricted to a caller-validated status window and an explicit screen permission.
    static func image(_ id: CGWindowID) -> CGImage? {
        guard CGPreflightScreenCaptureAccess(),
              let connection = symbol("CGSMainConnectionID", as: Connection.self),
              let capture = symbol("SLSHWCaptureWindowList", as: Capture.self) else { return nil }
        var window = id
        guard let images = capture(connection(), &window, 1, 0)?.takeRetainedValue(),
              CFArrayGetCount(images) == 1,
              let pointer = CFArrayGetValueAtIndex(images, 0) else { return nil }
        let value = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
        guard CFGetTypeID(value) == CGImage.typeID else { return nil }
        return (value as! CGImage)
    }

    static func frame(_ id: CGWindowID) -> CGRect? {
        guard let connection = symbol("CGSMainConnectionID", as: Connection.self),
              let query = symbol("CGSGetScreenRectForWindow", as: Bounds.self) else { return nil }
        var rectangle = CGRect.zero
        return query(connection(), id, &rectangle) == 0 ? rectangle : nil
    }
}
