import AppKit
import ApplicationServices
import FoldBarCore

/// Reorders the original status items. Never creates replacement application buttons.
@MainActor final class NativeMenuMover {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private struct Display {
        let screen: CGRect
        let band: CGRect
        let notch: CGRect?
    }
    private let displays: [Display]
    private var unselected: [MenuEntry] = []
    private(set) var fixedNames: [String] = []

    init() {
        let height = NSScreen.screens.first?.frame.height ?? 0
        displays = NSScreen.screens.map { screen in
            let frame = BarGeometry.quartzRect(screen.frame, primaryHeight: height)
            let band = CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                              height: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
            var notch: CGRect?
            if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
               let right = screen.auxiliaryTopRightArea {
                notch = CGRect(x: left.maxX, y: frame.minY, width: right.minX - left.maxX,
                               height: screen.safeAreaInsets.top)
            }
            return Display(screen: frame, band: band, notch: notch)
        }
    }

    static func frame(_ entry: MenuEntry) -> CGRect? {
        let windows = NativeStatusWindow.all()
        if let id = entry.windowID, let window = windows.first(where: { $0.id == id && $0.pid == entry.pid }) { return window.frame }
        let peers = windows.filter { $0.pid == entry.pid }
        if entry.pinReference?.menuItem?.wasOnlyItem == true, peers.count == 1 { return peers[0].frame }
        guard let element = entry.element else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard let rect = AccessibilityService.frame(element), rect.width > 1, rect.height > 1 else { return nil }
        return rect
    }

    private func isVisible(_ rect: CGRect) -> Bool {
        displays.contains { display in
            display.band.insetBy(dx: 0, dy: -1).contains(rect) &&
                !(display.notch?.intersects(rect) ?? false)
        }
    }

    // macOS reserves these controls. Their presence must never be reported as hidden.
    static func isFixed(_ entry: MenuEntry) -> Bool {
        guard entry.pinReference?.bundleID == "com.apple.controlcenter" ||
              entry.pinReference?.bundleID == "com.apple.systemuiserver" else { return false }
        let id = entry.pinReference?.menuItem?.identifier.lowercased() ?? ""
        return (id == "clock" || id.hasSuffix(".clock")) || (id == "controlcenter" || id.hasSuffix(".controlcenter")) ||
            ["控制中心", "Control Center", "时钟", "Clock"].contains(entry.name)
    }

    func place(_ entry: MenuEntry, before target: @escaping () -> CGRect?) async throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw Failure("请先开启辅助功能。") }
        guard !Self.isFixed(entry) else { throw Failure("此项目的位置由 macOS 固定。") }
        try await move(entry, toRight: false, divider: target)
        guard let frame = Self.frame(entry), isVisible(frame) else { throw Failure("原图标仍被遮挡，尚未显示到菜单栏。") }
    }

    func conceal(_ entry: MenuEntry, divider: @escaping () -> CGRect?) async throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw Failure("请先开启辅助功能。") }
        guard !Self.isFixed(entry) else { throw Failure("此项目的位置由 macOS 固定。") }
        try await move(entry, toRight: false, divider: divider)
    }

    private func waitForRelease() async throws {
        for _ in 0..<25 {
            let modifiers = CGEventSource.flagsState(.combinedSessionState)
            if !CGEventSource.buttonState(.combinedSessionState, button: .left),
               !CGEventSource.buttonState(.combinedSessionState, button: .right),
               modifiers.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty { return }
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        throw Failure("鼠标或修饰键仍按下；请松开后重试。")
    }

    private func move(_ entry: MenuEntry, toRight: Bool, divider: () -> CGRect?) async throws {
        try await waitForRelease()
        guard let original = Self.frame(entry), let boundary = divider(), isVisible(boundary) else {
            throw Failure("“\(entry.name)”或目标位置暂不可用。")
        }
        if NativeLayoutGeometry.isAdjacent(original, to: boundary, onRight: toRight) { return }
        let window = windowID(for: entry, frame: original)
        guard isVisible(original) || window != nil else {
            throw Failure("“\(entry.name)”被遮挡且没有对应原生窗口，无法移动。")
        }
        let destination = CGPoint(x: toRight ? boundary.maxX - 1 : boundary.minX + 1, y: boundary.midY)

        // AppKit's status-item tracking supports a window-addressed Command press followed
        // by release at the insertion boundary. Never post the offscreen source globally.
        if let window {
            try await sendDrag(entry, window: window, from: CGPoint(x: 20_000, y: 20_000),
                               to: destination, directed: true)
            if try await waitForPosition(entry, divider: divider, onRight: toRight) { return }
        }
        // Visible items can also use an ordinary Command-drag with an explicit modifier
        // key state. Re-read the position because a previous attempt may have shifted it.
        if let current = Self.frame(entry), isVisible(current), let currentTarget = divider(), isVisible(currentTarget) {
            let start = CGPoint(x: current.midX, y: current.midY)
            let finish = CGPoint(x: toRight ? currentTarget.maxX - 1 : currentTarget.minX + 1, y: currentTarget.midY)
            try await sendDrag(entry, window: window, from: start, to: finish, directed: false)
            if try await waitForPosition(entry, divider: divider, onRight: toRight) { return }
        }
        throw Failure("macOS 没有把“\(entry.name)”的原图标移到目标位置。")
    }

    private func waitForPosition(_ entry: MenuEntry, divider: () -> CGRect?, onRight: Bool) async throws -> Bool {
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let frame = Self.frame(entry), let boundary = divider(),
               NativeLayoutGeometry.isAdjacent(frame, to: boundary, onRight: onRight) { return true }
        }
        return false
    }

    private func sendDrag(_ entry: MenuEntry, window: CGWindowID?, from: CGPoint, to: CGPoint, directed: Bool) async throws {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            throw Failure("无法创建原图标拖动事件。")
        }
        down.flags = .maskCommand
        up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        commandDown.flags = .maskCommand
        commandUp.flags = []
        func send(_ event: CGEvent) {
            if directed, let window {
                event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
                event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
                event.postToPid(entry.pid)
            } else { event.post(tap: .cghidEventTap) }
        }
        if !directed { commandDown.post(tap: .cghidEventTap) }
        var buttonReleased = false
        defer {
            if !buttonReleased { send(up) }
            if !directed { commandUp.post(tap: .cghidEventTap) }
        }
        send(down)
        try await Task.sleep(nanoseconds: 180_000_000)
        if !directed {
            for step in 1...12 {
                let fraction = CGFloat(step) / 12
                let position = CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
                if let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: position, mouseButton: .left) {
                    drag.flags = .maskCommand
                    send(drag)
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        send(up)
        buttonReleased = true
    }

    private func windowID(for entry: MenuEntry, frame: CGRect) -> CGWindowID? {
        let candidates = NativeStatusWindow.all().filter { $0.pid == entry.pid }
        if let id = entry.windowID, candidates.contains(where: { $0.id == id }) { return id }
        return candidates.first { abs($0.frame.minX - frame.minX) < 3 && abs($0.frame.width - frame.width) < 6 }?.id
    }
}
