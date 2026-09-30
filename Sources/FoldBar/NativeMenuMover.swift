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

    nonisolated static func frame(_ entry: MenuEntry) -> CGRect? {
        let windows = NativeStatusWindow.all()
        if let id = entry.windowID, let window = windows.first(where: { $0.id == id && $0.pid == (entry.windowPID ?? entry.pid) }) { return window.frame }
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
    nonisolated static func isFixed(_ entry: MenuEntry) -> Bool {
        guard entry.pinReference?.bundleID == "com.apple.controlcenter" ||
              entry.pinReference?.bundleID == "com.apple.systemuiserver" else { return false }
        let id = entry.pinReference?.menuItem?.identifier.lowercased() ?? ""
        return (id == "clock" || id.hasSuffix(".clock")) || (id == "controlcenter" || id.hasSuffix(".controlcenter")) ||
            ["控制中心", "Control Center", "时钟", "Clock"].contains(entry.name)
    }

    func place(_ entry: MenuEntry, onRight: Bool = false, before target: @escaping () -> CGRect?) async throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw Failure("请先开启辅助功能。") }
        guard !Self.isFixed(entry) else { throw Failure("此项目的位置由 macOS 固定。") }
        try await move(entry, toRight: onRight, divider: target)
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

        // Address only the original status window; no events enter the global HID stream.
        if let window {
            try await sendDrag(entry, window: window, from: CGPoint(x: original.midX, y: original.midY),
                               to: destination)
            if try await waitForPosition(entry, divider: divider, onRight: toRight) { return }
        }
        // Some status windows only respond through the system event stream. Use one
        // insertion event with the cursor hidden, never an animated horizontal sweep.
        if let current = Self.frame(entry), isVisible(current), let target = divider(), isVisible(target) {
            try await insertWithoutPointerAnimation(from: CGPoint(x: current.midX, y: current.midY),
                to: CGPoint(x: toRight ? target.maxX - 1 : target.minX + 1, y: target.midY))
            if try await waitForPosition(entry, divider: divider, onRight: toRight) { return }
        }
        throw Failure("macOS 没有确认“\(entry.name)”的原图标位置。")
    }

    private func waitForPosition(_ entry: MenuEntry, divider: () -> CGRect?, onRight: Bool) async throws -> Bool {
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let frame = Self.frame(entry), let boundary = divider(),
               NativeLayoutGeometry.isAdjacent(frame, to: boundary, onRight: onRight) { return true }
        }
        return false
    }

    private func sendDrag(_ entry: MenuEntry, window: CGWindowID, from: CGPoint, to: CGPoint) async throws {
        // NSEvent supplies the target window number used by AppKit's dispatcher.
        // Pointer-position metadata alone does not route events to that window.
        func make(_ type: NSEvent.EventType, at point: CGPoint, flags: NSEvent.ModifierFlags) -> CGEvent? {
            guard let event = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: Int(window), context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)?.cgEvent else { return nil }
            event.location = point
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(entry.windowPID ?? entry.pid))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
            return event
        }
        guard let down = make(.leftMouseDown, at: from, flags: .command),
              let drag = make(.leftMouseDragged, at: to, flags: .command),
              let up = make(.leftMouseUp, at: to, flags: []) else {
            throw Failure("无法创建原图标移动事件。")
        }
        func send(_ event: CGEvent) { event.postToPid(entry.windowPID ?? entry.pid) }
        var released = false
        defer { if !released { send(up) } }
        send(down)
        try await Task.sleep(nanoseconds: 100_000_000)
        send(drag)
        try await Task.sleep(nanoseconds: 80_000_000)
        send(up)
        released = true
    }

    private func insertWithoutPointerAnimation(from: CGPoint, to: CGPoint) async throws {
        try await waitForRelease()
        guard let source = CGEventSource(stateID: .privateState), let pointer = CGEvent(source: nil)?.location,
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left),
              let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: to, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            throw Failure("无法创建原图标移动事件。")
        }
        guard CGDisplayHideCursor(CGMainDisplayID()) == .success else {
            throw Failure("无法完成无轨迹移动，已取消。")
        }
        down.flags = .maskCommand
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        drag.flags = .maskCommand
        up.flags = []
        keyDown.flags = .maskCommand
        keyUp.flags = []
        var lastPoint = from
        var finished = false
        defer {
            if !finished { up.location = lastPoint; up.post(tap: .cghidEventTap) }
            keyUp.post(tap: .cghidEventTap)
            // Don't undo a fresh physical mouse movement during this short operation.
            if let current = CGEvent(source: nil)?.location, hypot(current.x - lastPoint.x, current.y - lastPoint.y) < 3 {
                CGWarpMouseCursorPosition(pointer)
            }
            CGDisplayShowCursor(CGMainDisplayID())
        }
        keyDown.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 80_000_000)
        if let current = CGEvent(source: nil)?.location, hypot(current.x - from.x, current.y - from.y) >= 3 {
            throw Failure("检测到新的鼠标操作，已取消移动。")
        }
        lastPoint = to
        drag.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 60_000_000)
        up.post(tap: .cghidEventTap)
        finished = true
    }

    private func windowID(for entry: MenuEntry, frame: CGRect) -> CGWindowID? {
        let candidates = NativeStatusWindow.all().filter { $0.pid == (entry.windowPID ?? entry.pid) }
        if let id = entry.windowID, candidates.contains(where: { $0.id == id }) { return id }
        return candidates.first { abs($0.frame.minX - frame.minX) < 3 && abs($0.frame.width - frame.width) < 6 }?.id
    }
}
