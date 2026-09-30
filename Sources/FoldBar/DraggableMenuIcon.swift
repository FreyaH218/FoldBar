import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An actual AppKit drag session can leave the shelf and enter the menu bar.
struct DraggableMenuIcon: NSViewRepresentable {
    let entry: MenuEntry
    let model: AppModel

    func makeNSView(context: Context) -> MenuIconControl { MenuIconControl() }
    func updateNSView(_ view: MenuIconControl, context: Context) {
        view.entry = entry
        view.model = model
        view.icon = model.nativeIcons[entry.id]
        view.imageSize = model.iconSize(entry)
        view.toolTip = entry.name + " · 拖到顶部菜单栏显示，单击打开菜单"
        view.setAccessibilityLabel(entry.name)
        view.setAccessibilityValue(model.isShown(entry) ? "常驻菜单栏" : "隐藏项目")
        view.needsDisplay = true
    }
}

final class MenuIconControl: NSView, NSDraggingSource {
    var entry: MenuEntry?
    weak var model: AppModel?
    var icon: NSImage?
    var imageSize = CGSize(width: 24, height: 24)
    private var pressedEvent: NSEvent?
    private var inDrag = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || pressedEvent != nil {
            NSColor.labelColor.withAlphaComponent(0.09).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        }
        let rect = NSRect(x: bounds.midX - imageSize.width / 2, y: bounds.midY - imageSize.height / 2,
                          width: imageSize.width, height: imageSize.height)
        if let icon {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: model?.applyingNativeLayout == true ? 0.4 : 1)
        } else {
            // A short text placeholder is explicit; never substitute the application's logo.
            let text = String((entry?.name ?? "?").prefix(2)) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard model?.applyingNativeLayout == false else { return }
        pressedEvent = event
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        let clicked = pressedEvent != nil && !inDrag && bounds.contains(convert(event.locationInWindow, from: nil))
        pressedEvent = nil
        needsDisplay = true
        if clicked, let entry { model?.activate(entry) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard !inDrag, let down = pressedEvent, let entry, let model,
              hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y) >= 4,
              model.beginDrag(entry) else { return }
        inDrag = true
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(entry.id.utf8), forType: NSPasteboard.PasteboardType(UTType.foldBarApplication.identifier))
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(NSRect(x: bounds.midX - imageSize.width / 2, y: bounds.midY - imageSize.height / 2, width: imageSize.width, height: imageSize.height), contents: icon ?? NSImage(size: imageSize))
        let session = beginDraggingSession(with: [item], event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        inDrag = false
        pressedEvent = nil
        hovered = false
        needsDisplay = true
        model?.endDrag()
    }
    override func accessibilityPerformPress() -> Bool {
        guard let entry, let model, !model.applyingNativeLayout else { return false }
        model.activate(entry)
        return true
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let entry, let model, !model.applyingNativeLayout else { return nil }
        let menu = NSMenu()
        if entry.canOpenMenu { menu.addItem(withTitle: "打开原菜单", action: #selector(openOriginal), keyEquivalent: "").target = self }
        menu.addItem(withTitle: model.isShown(entry) ? "收回隐藏区" : "常驻菜单栏", action: #selector(changeVisibility), keyEquivalent: "").target = self
        return menu
    }
    @objc private func openOriginal() { if let entry { model?.onOpenEntry(entry) } }
    @objc private func changeVisibility() {
        guard let entry, let model else { return }
        if model.isShown(entry) { model.onHideEntry(entry) } else { model.onPlaceEntry(entry, nil) }
    }
}
