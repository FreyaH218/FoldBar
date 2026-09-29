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
    @Published var collapsed = false
    @Published var query = ""
    @Published var tab = 0
    @Published var settings = false
    @Published var notice: String?
    @Published var lastScanned: Date?
    @Published var shortcutAvailable = true
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var autoCollapse = UserDefaults.standard.object(forKey: "autoCollapse") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCollapse, forKey: "autoCollapse") }
    }
    @Published var nativeLayoutStatus = "把下方被隐藏的图标拖入显示区"
    @Published var applyingNativeLayout = false
    @Published var dividerFrame: CGRect?
    let service = AccessibilityService()
    var onToggleBar: () -> Void = {}
    var onClose: () -> Void = {}
    var onReset: () -> Void = {}
    var onOpenEntry: (MenuEntry) -> Void = { _ in }
    var onPlaceEntry: (MenuEntry, MenuEntry?) -> Void = { _, _ in }
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

    func dragProvider(for entry: MenuEntry) -> NSItemProvider {
        draggedEntry = entry
        let provider = NSItemProvider()
        provider.suggestedName = entry.name
        provider.registerDataRepresentation(forTypeIdentifier: UTType.foldBarApplication.identifier, visibility: .ownProcess) { completion in
            completion(Data(entry.id.utf8), nil)
            return nil
        }
        return provider
    }

    func acceptDrop(_ providers: [NSItemProvider], before target: MenuEntry? = nil, hide: Bool = false) -> Bool {
        guard !applyingNativeLayout, let snapshot = draggedEntry,
              let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.foldBarApplication.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.foldBarApplication.identifier) { [weak self] data, _ in
            guard let data, data.count <= 4096, String(data: data, encoding: .utf8) == snapshot.id else { return }
            DispatchQueue.main.async {
                guard let self, !self.applyingNativeLayout, snapshot.id != target?.id else { return }
                if hide { self.onHideEntry(snapshot) }
                else { self.onPlaceEntry(snapshot, target) }
            }
        }
        return true
    }

    func refresh() {
        trusted = AccessibilityService.trusted
        dividerFrame = currentDivider()
        applications = AccessibilityService.applications()
        guard trusted else { entries = []; scanning = false; return }
        guard !scanning, !applyingNativeLayout else { return }
        scanning = true
        service.scan(apps: applications) { [weak self] entries, _ in
            guard let self else { return }
            self.trusted = AccessibilityService.trusted
            self.entries = self.trusted ? entries : []
            self.dividerFrame = self.currentDivider()
            self.scanning = false
            self.lastScanned = Date()
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
