import AppKit
import UniformTypeIdentifiers

/// Exists only while dragging. The real menu bar doesn't accept our pasteboard type.
final class MenuBarDropTarget {
    private var panel: NSPanel?

    func show(frame: CGRect, entryID: String, onDrop: @escaping (CGPoint) -> Void) {
        hide()
        guard frame.width > 0, frame.height > 0 else { return }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let target = MenuBarDropView(frame: NSRect(origin: .zero, size: frame.size))
        target.entryID = entryID
        target.onDrop = onDrop
        panel.contentView = target
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil); panel = nil }
}

private final class MenuBarDropView: NSView {
    var entryID = ""
    var onDrop: (CGPoint) -> Void = { _ in }
    private var hovering = false
    private let type = NSPasteboard.PasteboardType(UTType.foldBarApplication.identifier)
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([type])
        setAccessibilityElement(true)
        setAccessibilityLabel("拖到这里，在原菜单栏显示")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard sender.draggingSource is MenuIconControl,
              let data = sender.draggingPasteboard.data(forType: type), data.count <= 4096,
              String(data: data, encoding: .utf8) == entryID else { return false }
        return bounds.contains(convert(sender.draggingLocation, from: nil))
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hovering = accepts(sender)
        needsDisplay = true
        return hovering ? .move : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false; needsDisplay = true }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard accepts(sender), let window else { return false }
        onDrop(window.convertPoint(toScreen: sender.draggingLocation))
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        NSColor.controlAccentColor.withAlphaComponent(hovering ? 0.24 : 0.10).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
