import AppKit

/// Native status-window inventory, including windows outside the visible display.
struct NativeStatusWindow {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let title: String
    let owner: String

    static func all() -> [NativeStatusWindow] {
        guard let list = MenuWindowBridge.descriptions() ?? (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)),
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let fallback = CGRect(dictionaryRepresentation: bounds) else { return nil }
            let rect = MenuWindowBridge.frame(id) ?? fallback
            guard
                  rect.width > 1, rect.width < 800, rect.height > 1, rect.height < 90 else { return nil }
            return NativeStatusWindow(id: id, pid: pid, frame: rect,
                title: info[kCGWindowName as String] as? String ?? "",
                owner: info[kCGWindowOwnerName as String] as? String ?? "菜单栏项目")
        }
    }
}
