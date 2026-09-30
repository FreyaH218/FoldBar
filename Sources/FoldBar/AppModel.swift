import AppKit
import SwiftUI
import ServiceManagement
import FoldBarCore
import UniformTypeIdentifiers

extension UTType {
    static let foldBarApplication = UTType(exportedAs: "local.foldbar.application-reference", conformingTo: .data)
}

final class AppModel: ObservableObject {
    @Published var entries: [MenuEntry] = []
    @Published var applications: [AppRecord] = []
    @Published var trusted = AccessibilityService.trusted
    @Published var scanning = false
    @Published var iconPermission = NativeIconCapture.permitted
    @Published var nativeIcons: [String: NSImage] = [:]
    @Published var capturingIcons = false
    private var iconTask: Task<Void, Never>?
    @Published var collapsed = false
    @Published var query = ""
    @Published var tab = 0
    @Published var settings = false
    @Published var searching = false
    @Published var notice: String?
    @Published var lastScanned: Date?
    @Published var shortcutAvailable = true
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var autoCollapse = UserDefaults.standard.object(forKey: "autoCollapse") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCollapse, forKey: "autoCollapse") }
    }
    @Published var nativeLayoutStatus = "直接把图标拖到屏幕顶部菜单栏"
    @Published var applyingNativeLayout = false
    @Published var dragging = false
    @Published var dividerFrame: CGRect?
    let service = AccessibilityService()
    var onToggleBar: () -> Void = {}
    var onClose: () -> Void = {}
    var onReset: () -> Void = {}
    var onOpenEntry: (MenuEntry) -> Void = { _ in }
    var onPlaceEntry: (MenuEntry, MenuEntry?) -> Void = { _, _ in }
    var onDragBegan: (MenuEntry) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    var onHideEntry: (MenuEntry) -> Void = { _ in }
    var onQuit: () -> Void = {}
    var onShow: () -> Void = {}
    var currentDivider: () -> CGRect? = { nil }
    var collapseSupported: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 }
    private var draggedEntry: MenuEntry?

    func isShown(_ entry: MenuEntry) -> Bool {
        guard let frame = entry.frame, let divider = dividerFrame else { return false }
        return frame.minX >= divider.maxX - 1 && abs(frame.midY - divider.midY) < 10 && !entry.obscured
    }
    var shownEntries: [MenuEntry] { entries.filter(isShown) }
    var filteredEntries: [MenuEntry] { entries.filter { ItemSearch.matches(query, name: $0.name, detail: $0.detail) } }
    var hiddenEntries: [MenuEntry] { filteredEntries.filter { !isShown($0) } }
    var barEntries: [MenuEntry] { searching ? filteredEntries : hiddenEntries }
    var feedback: String? {
        if let notice { return notice }
        return nativeLayoutStatus.hasPrefix("未移动") || nativeLayoutStatus.hasPrefix("请先") ? nativeLayoutStatus : nil
    }
    var panelSize: CGSize {
        let contentWidth = max(stripWidth(barEntries), settings ? stripWidth(shownEntries) : 0)
        let width = trusted ? min(720, max(settings || searching ? 400 : 260, contentWidth + 68)) : 340
        return CGSize(width: width, height: 52 + (settings && trusted ? 104 : 0) + (searching && trusted ? 44 : 0) + (feedback != nil ? 36 : 0))
    }

    func iconSize(_ entry: MenuEntry) -> CGSize {
        // The image includes the original status window's padding. Keep its point size.
        nativeIcons[entry.id]?.size ?? entry.frame?.size ?? CGSize(width: 24, height: 24)
    }

    func stripWidth(_ entries: [MenuEntry]) -> CGFloat {
        entries.reduce(0) { $0 + max(20, iconSize($1).width) + 2 }
    }

    func refreshIcons() {
        iconPermission = NativeIconCapture.permitted
        guard iconPermission, !dragging, !capturingIcons else { return }
        capturingIcons = true
        let snapshot = entries
        iconTask = Task { @MainActor [weak self] in
            let images = await NativeIconCapture.capture(snapshot)
            guard let self else { return }
            if !self.dragging {
                let live = Set(self.entries.map(\.id))
                self.nativeIcons = self.nativeIcons.filter { live.contains($0.key) }
                for (id, image) in images where live.contains(id) { self.nativeIcons[id] = image }
            }
            self.capturingIcons = false
        }
    }

    func grantIconPermission() {
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func showIconDiagnostics() {
        let alert = NSAlert()
        alert.messageText = "原始图标读取状态"
        alert.informativeText = iconPermission
            ? "已读取 \(nativeIcons.count) / \(entries.count) 个原始菜单栏图标。\n图像仅保存在内存中，不录音、不写入文件、不上传。"
            : "请先允许叠栏读取原始菜单栏图标。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func activate(_ entry: MenuEntry) {
        guard !applyingNativeLayout else { return }
        if entry.canOpenMenu { onOpenEntry(entry) }
        else { onPlaceEntry(entry, nil) }
    }

    func dismissFeedback() {
        notice = nil
        if feedback != nil { nativeLayoutStatus = "" }
    }

    func beginDrag(_ entry: MenuEntry) -> Bool {
        guard !applyingNativeLayout, !dragging, trusted else { return false }
        draggedEntry = entry
        dragging = true
        onDragBegan(entry)
        return true
    }

    func endDrag() {
        onDragEnded()
        dragging = false
        draggedEntry = nil
    }

    func acceptDrop(_ providers: [NSItemProvider], before target: MenuEntry? = nil, hide: Bool = false) -> Bool {
        guard dragging, !applyingNativeLayout, let snapshot = draggedEntry,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.foldBarApplication.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.foldBarApplication.identifier) { [weak self] data, _ in
            guard let data, data.count <= 4096, String(data: data, encoding: .utf8) == snapshot.id else { return }
            DispatchQueue.main.async {
                guard let self, !self.applyingNativeLayout, snapshot.id != target?.id else { return }
                if hide {
                    guard self.isShown(snapshot) else { return }
                    self.onHideEntry(snapshot)
                }
                else { self.onPlaceEntry(snapshot, target) }
            }
        }
        return true
    }

    func refresh() {
        guard !dragging else { return }
        trusted = AccessibilityService.trusted
        iconPermission = NativeIconCapture.permitted
        dividerFrame = currentDivider()
        applications = AccessibilityService.applications()
        guard trusted else { entries = []; scanning = false; return }
        guard !scanning, !applyingNativeLayout else { return }
        scanning = true
        service.scan(apps: applications) { [weak self] entries, _ in
            guard let self else { return }
            self.trusted = AccessibilityService.trusted
            if !self.dragging { self.entries = self.trusted ? entries : [] }
            self.dividerFrame = self.currentDivider()
            self.scanning = false
            self.lastScanned = Date()
            self.refreshIcons()
        }
    }

    func grantPermission() {
        AccessibilityService.requestPermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openApp(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            notice = "该应用已退出，请刷新列表。"; refresh(); return
        }
        onClose()
        app.activate(options: [.activateIgnoringOtherApps])
    }

    func toggleLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            notice = "未能更改登录项：\(error.localizedDescription)"
        }
    }
}
