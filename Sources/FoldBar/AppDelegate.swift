import AppKit
import SwiftUI
import Carbon
import FoldBarCore
import Combine

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

final class GlobalHotKeys {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    var action: ((UInt32) -> Void)?

    func register() -> Bool {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let owner = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
            owner.action?(id.id)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return false }
        var allRegistered = true
        for id: UInt32 in [1, 2] {
            var ref: EventHotKeyRef?
            let modifiers = UInt32(cmdKey | optionKey | (id == 2 ? shiftKey : 0))
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_B), modifiers,
                EventHotKeyID(signature: 0x46426172, id: id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { keys.append(ref) } else { allRegistered = false }
        }
        return allRegistered
    }

    deinit {
        keys.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var toggle: NSStatusItem!
    private var separator: NSStatusItem!
    private var layoutTask: Task<Void, Never>?
    private var layoutVerified = false
    private var panel: ShelfPanel!
    private var host: NSHostingView<AnyView>!
    private var sizeObservation: AnyCancellable?
    private let hotKeys = GlobalHotKeys()
    private var permissionTimer: Timer?
    private var collapseTimer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastExpanded = Date()
    private var lastRefresh = Date.distantPast
    private var observerTokens: [NSObjectProtocol] = []
    private var actionGeneration = 0
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !smokeTest, let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "local.foldbar.app")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        createStatusItems()
        createPanel()
        sizeObservation = model.objectWillChange
            .debounce(for: .milliseconds(60), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.positionPanel()
            }
        model.onToggleBar = { [weak self] in self?.setCollapsed(!(self?.model.collapsed ?? false)) }
        model.onClose = { [weak self] in self?.hidePanel() }
        model.onShow = { [weak self] in self?.showPanel() }
        model.currentDivider = { [weak self] in
            guard let self, let divider = self.separator else { return nil }
            return self.nativeFrame(divider)
        }
        model.onPlaceEntry = { [weak self] entry, before in self?.moveNativeEntry(entry, before: before, hide: false) }
        model.onHideEntry = { [weak self] entry in self?.moveNativeEntry(entry, before: nil, hide: true) }
        model.onReset = { [weak self] in self?.resetPositions() }
        model.onOpenEntry = { [weak self] entry in self?.openEntry(entry) }
        model.onQuit = { NSApp.terminate(nil) }
        hotKeys.action = { [weak self] id in
            if id == 1 { self?.togglePanel() }
            else { self?.model.onToggleBar() }
        }
        model.shortcutAvailable = hotKeys.register()
        installMonitors()
        observeChanges()
        model.refresh()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trust = AccessibilityService.trusted
            if self.model.trusted != trust { self.model.refresh() }
            if self.panel.isVisible && Date().timeIntervalSince(self.lastRefresh) > 12 {
                self.model.refresh(); self.lastRefresh = Date()
            }
        }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.autoCollapseIfNeeded()
        }
        // Let the system restore saved status-item positions before any width changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if self.smokeTest { self.runSmokeTest(); return }
            self.setCollapsed(false)
            self.model.nativeLayoutStatus = "把下方被遮挡的图标拖到显示区，即可尝试移到顶部"
            self.showPanel()
        }
    }

    private func createStatusItems() {
        let defaults = UserDefaults.standard
        // Start with a visible boundary; selected original items will be moved to its right.
        for (name, position) in [("FoldBar.Toggle", 0), ("FoldBar.Divider", 1)] {
            let key = "NSStatusItem Preferred Position \(name)"
            if defaults.object(forKey: key) == nil { defaults.set(position, forKey: key) }
        }
        toggle = NSStatusBar.system.statusItem(withLength: 30)
        toggle.autosaveName = "FoldBar.Toggle"
        toggle.behavior = []
        toggle.button?.target = self
        toggle.button?.action = #selector(statusClicked)
        toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        toggle.button?.setAccessibilityLabel("叠栏：显示所有菜单栏项目")

        separator = NSStatusBar.system.statusItem(withLength: 18)
        separator.autosaveName = "FoldBar.Divider"
        separator.behavior = []
        separator.button?.image = NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "折叠分隔线")
        separator.button?.image?.isTemplate = true
        separator.button?.target = self
        separator.button?.action = #selector(dividerClicked)
        separator.button?.toolTip = "按住 ⌘，将要折叠的图标拖到这条分隔线左侧"
        updateStatusImage()
    }

    private func createPanel() {
        panel = ShelfPanel(contentRect: NSRect(origin: .zero, size: model.panelSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "叠栏 FoldBar"
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        host = NSHostingView(rootView: AnyView(ShelfView(model: model).frame(width: model.panelSize.width, height: model.panelSize.height)))
        host.sizingOptions = []
        panel.contentView = host
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true { model.onToggleBar(); return }
        togglePanel()
    }

    @objc private func dividerClicked() { model.onToggleBar() }
    @objc private func toggleOriginalBar() { model.onToggleBar() }
    @objc private func openShelfMenu() { showPanel() }
    @objc private func openSettingsMenu() { model.settings = true; showPanel() }
    @objc private func resetFromMenu() { resetPositions() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }

    private func showContextMenu() {
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            ("显示隐藏图标", #selector(openShelfMenu)),
            (model.collapsed ? "展开原菜单栏" : "收起原菜单栏", #selector(toggleOriginalBar)),
            ("整理图标…", #selector(openSettingsMenu)),
            ("恢复分隔线位置", #selector(resetFromMenu))
        ]
        for (title, selector) in items { let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: ""); item.target = self }
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出叠栏", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    func setCollapsed(_ collapsed: Bool) {
        guard model.collapseSupported || !collapsed else { return }
        model.collapsed = collapsed
        separator.length = collapsed ? 4096 : 18
        separator.button?.image = collapsed ? nil : NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "折叠分隔线")
        if !collapsed { lastExpanded = Date() }
        if !smokeTest { UserDefaults.standard.set(collapsed, forKey: "collapsed") }
        updateStatusImage()
        if panel.isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.model.refresh() }
        }
    }

    private func updateStatusImage() {
        let symbol = "ellipsis"
        toggle.length = 30
        toggle.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "叠栏")
        toggle.button?.image?.isTemplate = true
        toggle.button?.toolTip = "叠栏 · 管理原生菜单栏图标 · ⌥⌘B"
        toggle.button?.setAccessibilityLabel("叠栏：管理原生菜单栏图标")
    }

    private func nativeFrame(_ item: NSStatusItem) -> CGRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return BarGeometry.quartzRect(window.convertToScreen(button.convert(button.bounds, to: nil)),
                                      primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    private func moveNativeEntry(_ entry: MenuEntry, before target: MenuEntry?, hide: Bool) {
        guard !model.applyingNativeLayout else { return }
        guard AccessibilityService.trusted else { model.nativeLayoutStatus = "请先开启辅助功能。"; return }
        model.applyingNativeLayout = true
        model.nativeLayoutStatus = "正在移动“\(entry.name)”的原图标…"
        layoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                self.hidePanel()
                self.setCollapsed(false)
                try await Task.sleep(nanoseconds: 250_000_000)
                let mover = NativeMenuMover()
                if hide {
                    try await mover.conceal(entry, divider: { self.nativeFrame(self.separator) })
                } else {
                    try await mover.place(entry, before: {
                        if let target { return NativeMenuMover.frame(target) }
                        return self.nativeFrame(self.toggle)
                    })
                }
                self.setCollapsed(true)
                try await Task.sleep(nanoseconds: 300_000_000)
                if !hide {
                    guard let frame = NativeMenuMover.frame(entry), let divider = self.nativeFrame(self.separator),
                          frame.minX >= divider.maxX - 1 else {
                        throw NativeMenuMover.Failure("原图标未移到显示区，已恢复展开。")
                    }
                }
                self.layoutVerified = true
                self.model.nativeLayoutStatus = "“\(entry.name)”的原图标已" + (hide ? "收回隐藏区" : "移到顶部")
            } catch {
                self.setCollapsed(false)
                self.model.nativeLayoutStatus = "未移动：" + error.localizedDescription
            }
            self.model.applyingNativeLayout = false
            self.showPanel()
        }
    }

    private func togglePanel() { panel.isVisible ? hidePanel() : showPanel() }

    private func showPanel() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        model.refresh()
        lastRefresh = Date()
        updateStatusImage()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        lastExpanded = Date()
        updateStatusImage()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = (panel.isVisible ? panel.screen : nil) ?? NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let inset = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let desired = model.panelSize
        let size = CGSize(width: min(desired.width, screen.frame.width - 24), height: min(desired.height, screen.frame.height - inset - 36))
        var anchor = CGPoint(x: screen.frame.midX, y: screen.frame.maxY)
        if let button = toggle.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if screen.frame.contains(rect) { anchor.x = rect.midX }
        }
        let origin = BarGeometry.panelOrigin(anchor: anchor, size: size, screen: screen.frame, topInset: inset)
        if panel.frame.size != size {
            host.rootView = AnyView(ShelfView(model: model).frame(width: size.width, height: size.height))
            panel.contentMinSize = .zero
            panel.contentMaxSize = screen.frame.size
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func openEntry(_ entry: MenuEntry) {
        guard AccessibilityService.trusted else { model.refresh(); return }
        guard NSRunningApplication(processIdentifier: entry.pid)?.isTerminated == false else {
            model.notice = "该应用已退出，请刷新列表。"; model.refresh(); showPanel(); return
        }
        actionGeneration += 1
        let generation = actionGeneration
        hidePanel()
        // Restore the real status item before asking it to open its menu.
        setCollapsed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, generation == self.actionGeneration else { return }
            self.model.service.open(entry) { [weak self] result in
                guard let self, generation == self.actionGeneration else { return }
                if result == .success { return }
                if result == .cannotComplete {
                    self.model.notice = "\(entry.name) 尚未确认菜单是否打开。若没有出现，请右键该项目选择“打开应用”。"
                    return
                }
                self.model.notice = "\(entry.name) 无法直接打开菜单（\(result.rawValue)）。可右键项目选择“打开应用”，或按住 ⌘ 将原图标拖到刘海右侧。"
                self.showPanel()
            }
        }
    }

    private func resetPositions() {
        actionGeneration += 1
        setCollapsed(false)
        NSStatusBar.system.removeStatusItem(separator)
        NSStatusBar.system.removeStatusItem(toggle)
        UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position FoldBar.Toggle")
        UserDefaults.standard.set(1, forKey: "NSStatusItem Preferred Position FoldBar.Divider")
        createStatusItems()
        layoutVerified = false
        model.nativeLayoutStatus = "分隔线已恢复，把需要的原图标拖入显示区。"
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.hidePanel()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible { self.hidePanel(); return nil }
            if (event.type == .leftMouseDown || event.type == .rightMouseDown), self.panel.isVisible,
               event.window !== self.panel && event.window !== self.toggle.button?.window { self.hidePanel() }
            return event
        }
    }

    private func observeChanges() {
        observerTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.actionGeneration += 1
                self.layoutVerified = false
                self.setCollapsed(false)
                if self.panel.isVisible { self.positionPanel(); self.model.refresh() }
            })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observerTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if self.panel.isVisible { self.model.refresh() }
            })
        }
    }

    private func autoCollapseIfNeeded() {
        guard !smokeTest, layoutVerified, !model.applyingNativeLayout, model.autoCollapse, !model.collapsed, !panel.isVisible,
              Date().timeIntervalSince(lastExpanded) > 20 else { return }
        let mouse = NSEvent.mouseLocation
        if NSScreen.screens.contains(where: { $0.frame.contains(mouse) && mouse.y > $0.frame.maxY - max(32, $0.safeAreaInsets.top) }) { return }
        // Menu windows use the pop-up menu level; defer while a native menu is in use.
        if let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           windows.contains(where: { ($0[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.popUpMenuWindow)) }) { return }
        setCollapsed(true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }

    func applicationWillTerminate(_ notification: Notification) {
        actionGeneration += 1
        permissionTimer?.invalidate()
        collapseTimer?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        observerTokens.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        // Remove our own items so the original icons regain their space immediately.
        if let separator { separator.length = 18; NSStatusBar.system.removeStatusItem(separator) }
        if let toggle { NSStatusBar.system.removeStatusItem(toggle) }
    }

    /// A local smoke mode exercises real NSStatusItems and captures only this app's own view.
    private func runSmokeTest() {
        let output = ProcessInfo.processInfo.environment["FOLDBAR_SMOKE_DIR"] ?? NSTemporaryDirectory()
        showPanel()
        var report: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                                   "accessibilityGranted": model.trusted, "hotKeysRegistered": model.shortcutAvailable,
                                   "screens": NSScreen.screens.count]
        report["expandedLength"] = separator.length
        report["panelBelowMenuBar"] = panel.frame.maxY <= (NSScreen.main?.frame.maxY ?? 0) - NSStatusBar.system.thickness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.captureOwnView(to: output + "/foldbar-permission.png")
            self.setCollapsed(true)
            report["collapsedLength"] = self.separator.length
            report["collapseState"] = self.model.collapsed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                report["dividerWindowWidthCollapsed"] = self.separator.button?.window?.frame.width ?? 0
                report["toggleFrameX"] = self.toggle.button?.window?.frame.minX ?? -1
                self.setCollapsed(false)
                self.model.tab = 1
                report["expandedRestored"] = self.separator.length == 18 && !self.model.collapsed
                report["runningApps"] = self.model.applications.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.captureOwnView(to: output + "/foldbar-apps.png")
                    self.model.query = "__FOLDBAR_NO_MATCH__"
                    report["searchFiltersApps"] = self.model.filteredEntries.isEmpty
                    self.model.query = ""
                    self.model.settings = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.captureOwnView(to: output + "/foldbar-settings.png")
                        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                            try? data.write(to: URL(fileURLWithPath: output + "/smoke-report.json"))
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func captureOwnView(to path: String) {
        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
