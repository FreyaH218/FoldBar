import SwiftUI

/// The everyday surface is one row. Arrangement and search are opt-in.
struct ShelfView: View {
    @ObservedObject var model: AppModel
    @State private var hiddenTargeted = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.settings && model.trusted {
                PinnedShelfView(model: model)
                Divider().padding(.horizontal, 14)
            }
            if model.searching && model.trusted { searchField }
            HStack(spacing: 4) {
                if !model.trusted { permissionPrompt }
                else if !model.iconPermission { iconPermissionPrompt }
                else if model.barEntries.isEmpty { emptyState }
                else { MenuIconStrip(entries: model.barEntries, model: model) }
                Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22).padding(.horizontal, 3)
                if model.applyingNativeLayout {
                    ProgressView().controlSize(.small).frame(width: 36, height: 40).help(model.nativeLayoutStatus)
                } else { settingsMenu }
            }
            .padding(.horizontal, 10).frame(height: 52)
            .background(Color.accentColor.opacity(hiddenTargeted ? 0.12 : 0))
            .onDrop(of: [.foldBarApplication], isTargeted: $hiddenTargeted) { model.acceptDrop($0, hide: true) }
            if model.settings && model.trusted {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(hiddenTargeted ? "松开，收回隐藏区" : "直接拖到屏幕顶部显示 · 拖回这里隐藏")
                    Spacer(minLength: 0)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).frame(height: 26, alignment: .top)
            }
            if let feedback = model.feedback {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(feedback).lineLimit(1).help(feedback)
                    Spacer(minLength: 0)
                    Button(action: model.dismissFeedback) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("关闭提示")
                }.font(.system(size: 11)).padding(.horizontal, 16).frame(height: 36)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.24), lineWidth: 0.75))
        .onChange(of: model.dragging) { if !$0 { hiddenTargeted = false } }
        .onExitCommand {
            if model.searching { model.searching = false; model.query = "" }
            else if model.settings { model.settings = false }
            else { model.onClose() }
        }
    }

    private var permissionPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "menubar.rectangle").font(.system(size: 21)).foregroundStyle(.secondary)
            Button("允许访问菜单栏") { model.grantPermission() }.buttonStyle(.plain).font(.system(size: 13))
            Spacer(minLength: 0)
        }.padding(.leading, 6).help("开启辅助功能，读取和移动原生菜单栏图标")
    }

    private var iconPermissionPrompt: some View {
        Button("允许读取原始菜单栏图标") { model.grantIconPermission() }
            .buttonStyle(.plain).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6).help("仅截取菜单栏项目的静态图像，保留原图标及原始尺寸")
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            if model.scanning { ProgressView().controlSize(.small) }
            else { Image(systemName: model.searching ? "magnifyingglass" : "checkmark.circle").foregroundStyle(.secondary) }
            Text(model.scanning ? "正在读取图标…" : (model.searching ? "没有匹配的图标" : "没有隐藏的图标"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(.leading, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索全部菜单栏项目", text: $model.query).textFieldStyle(.plain)
                .focused($searchFocused).accessibilityLabel("搜索菜单栏图标")
            Button { model.searching = false; model.query = "" } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityLabel("关闭搜索")
        }.font(.system(size: 12)).padding(.horizontal, 17).frame(height: 44)
            .onAppear { searchFocused = true }
    }

    private var settingsMenu: some View {
        Menu {
            Button(model.settings ? "完成整理" : "管理常驻图标") { model.settings.toggle() }.disabled(!model.trusted)
            Button(model.searching ? "关闭搜索" : "搜索图标…") {
                model.searching.toggle(); if !model.searching { model.query = "" }
            }.disabled(!model.trusted)
            Button("刷新图标") { model.refresh() }.disabled(model.scanning)
            Divider()
            Button(model.collapsed ? "临时展开原菜单栏" : "收起隐藏区", action: model.onToggleBar).disabled(!model.collapseSupported)
            Toggle("临时展开 20 秒后收起", isOn: $model.autoCollapse)
            Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: model.toggleLogin))
            Divider()
            Button("辅助功能设置…") { model.grantPermission() }
            Button("原始图标读取权限…") { model.grantIconPermission() }
            Button("图标读取状态…") { model.showIconDiagnostics() }
            Button("恢复菜单栏布局", action: model.onReset)
            Divider()
            Text("叠栏 1.5 · ⌥⌘B 打开图标条")
            Button("关闭图标条", action: model.onClose)
            Button("退出叠栏", action: model.onQuit)
        } label: {
            Image(systemName: "gearshape").font(.system(size: 20, weight: .regular)).frame(width: 36, height: 40)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("叠栏设置").help("管理常驻图标与设置")
    }
}
