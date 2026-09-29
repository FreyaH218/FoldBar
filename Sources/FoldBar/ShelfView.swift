import SwiftUI

struct ShelfView: View {
    @ObservedObject var model: AppModel
    @State private var hiddenTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 23)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("叠栏").font(.system(size: 20, weight: .semibold))
                    Text("把被遮挡的原图标拖出来").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.settings.toggle() } label: { Image(systemName: model.settings ? "arrow.left" : "gearshape") }
                    .buttonStyle(.plain).accessibilityLabel(model.settings ? "返回菜单栏项目" : "设置")
                Button(action: model.onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭面板")
            }.padding(20)
            Divider().padding(.horizontal, 20)
            if model.settings { settingsPage } else { menuPage }
            HStack {
                Text("⌥⌘B 随时打开")
                Spacer()
                Text("FOLDBAR")
            }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(16)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.1)))
        .onExitCommand { model.onClose() }
    }

    private var menuPage: some View {
        VStack(spacing: 12) {
            HStack {
                Text(model.collapsed ? "隐藏区已收起" : "原菜单栏已展开").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(model.collapsed ? "临时展开全部" : "收起隐藏区", action: model.onToggleBar)
                    .font(.system(size: 11)).buttonStyle(.bordered)
                    .disabled(model.applyingNativeLayout || !model.collapseSupported)
            }
            PinnedShelfView(model: model)
            HStack {
                Text("菜单栏项目 · \(model.entries.count)").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { model.refresh() } label: {
                    if model.scanning { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }.buttonStyle(.plain).disabled(model.scanning || model.applyingNativeLayout).accessibilityLabel("刷新菜单栏项目")
            }
            TextField("搜索菜单栏图标…", text: $model.query).textFieldStyle(.roundedBorder)
                .accessibilityLabel("搜索菜单栏图标")
            if !model.trusted {
                VStack(alignment: .leading, spacing: 10) {
                    Label("读取和移动原图标需要辅助功能", systemImage: "lock")
                    Button("开启辅助功能") { model.grantPermission() }
                }.font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.filteredEntries) { entry in row(entry) }
                        if model.filteredEntries.isEmpty {
                            Text(model.scanning ? "正在识别菜单栏项目…" : "未找到匹配的菜单栏项目")
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(24)
                        }
                    }
                }
                .background(Color.accentColor.opacity(hiddenTargeted ? 0.08 : 0))
                .onDrop(of: [.foldBarApplication], isTargeted: $hiddenTargeted) { model.acceptDrop($0, hide: true) }
                Text("拖入显示区后显示原图标；拖回列表收起。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let notice = model.notice { Text(notice).font(.system(size: 11)).foregroundStyle(.secondary) }
        }.padding(20)
    }

    private func row(_ entry: MenuEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
            Image(nsImage: entry.icon).resizable().frame(width: 27, height: 27)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(model.isShown(entry) ? "顶部已显示" : (entry.obscured ? "被遮挡 · 可拖入显示区" : "隐藏区 · 可拖入显示区"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                if model.isShown(entry) { model.onHideEntry(entry) }
                else { model.onPlaceEntry(entry, nil) }
            } label: { Image(systemName: model.isShown(entry) ? "arrow.down.circle" : "arrow.up.circle").font(.system(size: 18)) }
                .buttonStyle(.plain).disabled(model.applyingNativeLayout)
                .accessibilityLabel("\(model.isShown(entry) ? "隐藏" : "显示")\(entry.name)的原图标")
        }
        .padding(10)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onDrag { model.dragProvider(for: entry) }
        .contextMenu {
            Button("显示到顶部") { model.onPlaceEntry(entry, nil) }
            Button("收回隐藏区") { model.onHideEntry(entry) }
            if entry.canOpenMenu { Button("打开原菜单") { model.onOpenEntry(entry) } }
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("从下方拖入显示区，显示应用原本的菜单栏图标。显示区按真实位置排列；拖到某项前面即可换序。拖回下方列表或右键可隐藏。")
                Text("时钟、控制中心等系统固定控件可能无法移动。没有菜单栏图标的应用不会加入此列表。移动未成功时会保留展开并提示原因。")
                    .foregroundStyle(.secondary)
                Divider()
                Toggle("临时展开 20 秒后收起", isOn: $model.autoCollapse)
                Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: model.toggleLogin))
                Divider()
                Text("⌥⌘B：打开面板\n⇧⌥⌘B：收起 / 展开隐藏区\n⌘ 拖动顶部原图标：手动调整位置")
                Label(model.trusted ? "辅助功能已开启" : "辅助功能未开启", systemImage: model.trusted ? "checkmark.circle" : "lock")
                Button("辅助功能设置") { model.grantPermission() }
                Button("恢复分隔线位置", action: model.onReset)
                Divider()
                Text("叠栏 1.3 · 本地开发验证版").fontWeight(.semibold)
                Text("原图标移动兼容性仍在验证。面板图片用于识别项目；顶部由原应用绘制。无网络请求。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("退出叠栏", action: model.onQuit)
            }.font(.system(size: 12)).padding(20)
        }
    }
}
