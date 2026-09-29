import AppKit
import ApplicationServices
import FoldBarCore

struct AppRecord: Identifiable {
    var id: Int32 { pid }
    let pid: pid_t
    let name: String
    let bundleID: String
    let bundlePath: String?
    let icon: NSImage
    let isAccessory: Bool

    var pinReference: PinnedApplication? {
        PinnedApplication(name: name, bundleID: bundleID, bundlePath: bundlePath)
    }
}

struct MenuEntry: Identifiable {
    let id: String
    let pid: pid_t
    let name: String
    let detail: String
    let icon: NSImage
    let element: AXUIElement?
    var windowID: CGWindowID? = nil
    let actions: [String]
    let frame: CGRect?
    let obscured: Bool
    let pinReference: PinnedApplication?
    var canOpenMenu: Bool { actions.contains(kAXPressAction) || actions.contains(kAXShowMenuAction) }
}

private struct RawEntry {
    let pid: pid_t
    let title: String
    let element: AXUIElement
    let actions: [String]
    let frame: CGRect?
    let identity: String
    let identifier: String
}

/// All cross-process accessibility calls run on a serial worker with timeouts.
/// This reader uses AX only; NativeMenuMover handles user-requested Command-drag layout changes.
final class AccessibilityService {
    private let queue = DispatchQueue(label: "local.foldbar.accessibility", qos: .userInitiated)

    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func applications() -> [AppRecord] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !app.isTerminated, let name = app.localizedName else { return nil }
            let isSystemBar = ["com.apple.controlcenter", "com.apple.systemuiserver"].contains(app.bundleIdentifier ?? "")
            guard app.activationPolicy != .prohibited || isSystemBar else { return nil }
            return AppRecord(pid: app.processIdentifier, name: name, bundleID: app.bundleIdentifier ?? "",
                             bundlePath: app.bundleURL?.path,
                             icon: app.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!,
                             isAccessory: app.activationPolicy != .regular)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func scan(apps: [AppRecord], completion: @escaping ([MenuEntry], Int) -> Void) {
        // Snapshot display geometry on the main thread. Screen IDs and coordinates may change on hotplug.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { BarGeometry.quartzRect($0.frame, primaryHeight: primaryHeight) }
        let notches = NSScreen.screens.compactMap { screen -> CGRect? in
            guard screen.safeAreaInsets.top > 0,
                  let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
            let notch = CGRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top,
                               width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
            return BarGeometry.quartzRect(notch, primaryHeight: primaryHeight)
        }

        queue.async {
            AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.15)
            var raw: [RawEntry] = []
            var unresponsive = 0
            for app in apps {
                let root = AXUIElementCreateApplication(app.pid)
                AXUIElementSetMessagingTimeout(root, 0.15)
                var extrasValue: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(root, kAXExtrasMenuBarAttribute as CFString, &extrasValue)
                if result == .cannotComplete { unresponsive += 1; continue }
                var roots: [AXUIElement] = []
                if let extrasValue, CFGetTypeID(extrasValue) == AXUIElementGetTypeID() {
                    roots.append(extrasValue as! AXUIElement)
                }
                // Some system extras are exposed as AXMenuBar instead of AXExtrasMenuBar.
                if roots.isEmpty && ["com.apple.controlcenter", "com.apple.systemuiserver"].contains(app.bundleID),
                   let menu = Self.element(root, kAXMenuBarAttribute) { roots.append(menu) }

                var seen: [AXUIElement] = []
                for menu in roots {
                    for item in Self.menuItems(in: menu) where !seen.contains(where: { CFEqual($0, item) }) {
                        seen.append(item)
                        let actions = Self.actions(item)
                        let title = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                            .compactMap { Self.string(item, $0) }
                            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
                        let itemID = Self.string(item, kAXIdentifierAttribute) ?? ""
                        raw.append(RawEntry(pid: app.pid, title: String(title.prefix(100)), element: item,
                                            actions: actions, frame: Self.frame(item),
                                            identity: "\(app.pid):\(itemID):\(CFHash(item))", identifier: itemID))
                    }
                }
            }
            DispatchQueue.main.async {
                let byPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0) })
                let counts = Dictionary(grouping: raw, by: \.pid).mapValues(\.count)
                var occurrences: [String: Int] = [:]
                let entries = raw.compactMap { item -> MenuEntry? in
                    guard let app = byPID[item.pid] else { return nil }
                    let isSystem = ["com.apple.controlcenter", "com.apple.systemuiserver"].contains(app.bundleID)
                    let title = item.title.replacingOccurrences(of: "\n", with: " ")
                    let name = isSystem && !title.isEmpty ? title : app.name
                    let detail = title.isEmpty || title == name ? (isSystem ? "系统菜单栏项目" : "菜单栏项目") : title
                    let key = "\(item.pid):" + (item.identifier.isEmpty ? "title:\(title)" : "id:\(item.identifier)")
                    let occurrence = occurrences[key, default: 0]
                    occurrences[key] = occurrence + 1
                    let reference = MenuItemReference(identifier: item.identifier, title: title,
                                                      occurrence: occurrence, wasOnlyItem: counts[item.pid] == 1)
                    let label = counts[item.pid, default: 0] > 1 && !title.isEmpty ? title : name
                    let pin = PinnedApplication(name: label, bundleID: app.bundleID,
                                                bundlePath: app.bundlePath, menuItem: reference)
                    return MenuEntry(id: item.identity, pid: item.pid, name: name, detail: detail,
                                     icon: app.icon, element: item.element, actions: item.actions, frame: item.frame,
                                     obscured: item.frame.map { BarGeometry.isObscured($0, screens: screens, notches: notches) } ?? true,
                                     pinReference: pin)
                }
                let windows = NativeStatusWindow.all()
                var remaining = entries
                var actual: [MenuEntry] = []
                for window in windows {
                    let peers = remaining.indices.filter { remaining[$0].pid == window.pid }
                    let exact = peers.first { index in
                        guard let frame = remaining[index].frame else { return false }
                        return abs(frame.minX - window.frame.minX) < 3 && abs(frame.width - window.frame.width) < 6
                    }
                    let matched = exact ?? (peers.count == 1 ? peers.first : nil)
                    let ax = matched.map { remaining.remove(at: $0) }
                    let app = byPID[window.pid]
                    let title = ax?.name ?? (window.title.isEmpty ? (app?.name ?? window.owner) : window.title)
                    let menu = MenuItemReference(identifier: "native-window:\(window.id)", title: window.title,
                                                 occurrence: 0, wasOnlyItem: windows.filter { $0.pid == window.pid }.count == 1)
                    let pin = ax?.pinReference ?? PinnedApplication(name: title, bundleID: app?.bundleID ?? "",
                        bundlePath: app?.bundlePath, menuItem: menu)
                    actual.append(MenuEntry(id: "window:\(window.id)", pid: window.pid, name: title,
                        detail: "原生菜单栏项目", icon: app?.icon ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)!,
                        element: ax?.element, windowID: window.id, actions: ax?.actions ?? [], frame: window.frame,
                        obscured: BarGeometry.isObscured(window.frame, screens: screens, notches: notches), pinReference: pin))
                }
                // Retain real AX items omitted by the public window list, including notch-clipped items.
                // Zero-frame Control Center placeholders are not actual menu-bar icons.
                actual += remaining.filter { entry in
                    guard let frame = entry.frame, frame.width > 1, frame.height > 1, frame.height < 90 else { return false }
                    return screens.contains { abs(frame.minY - $0.minY) < 40 }
                }
                completion(actual.sorted { ($0.frame?.minX ?? 0) < ($1.frame?.minX ?? 0) }, unresponsive)
            }
        }
    }

    func open(_ entry: MenuEntry, completion: @escaping (AXError) -> Void) {
        guard let element = entry.element else { completion(.actionUnsupported); return }
        queue.async {
            AXUIElementSetMessagingTimeout(element, 0.7)
            let available = Self.actions(element)
            let action = available.contains(kAXPressAction) ? kAXPressAction : kAXShowMenuAction
            guard available.contains(action) else {
                DispatchQueue.main.async { completion(.actionUnsupported) }
                return
            }
            // Only one advertised action is sent: retrying a timeout can accidentally close an opened menu.
            let result = AXUIElementPerformAction(element, action as CFString)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func element(_ root: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(root, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func menuItems(in root: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 128 {
            let (node, depth) = queue.removeFirst()
            visited += 1
            let role = string(node, kAXRoleAttribute) ?? ""
            if depth > 0 && (role == kAXMenuBarItemRole || role == kAXButtonRole) {
                result.append(node)
                continue // Never descend into menu commands and mistake them for status items.
            }
            if depth < 3, let children = value(node, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(80).map { ($0, depth + 1) })
            }
        }
        return result
    }

    private static func actions(_ element: AXUIElement) -> [String] {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success else { return [] }
        return actions as? [String] ?? []
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = value(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
