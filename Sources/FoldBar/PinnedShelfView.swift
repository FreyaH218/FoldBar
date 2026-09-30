import SwiftUI

struct PinnedShelfView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(targeted ? "松开，常驻顶部菜单栏" : "常驻菜单栏").foregroundStyle(.secondary)
                Spacer()
                Button("完成") { model.settings = false }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .accessibilityLabel("完成整理")
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 16).frame(height: 27)
            if model.shownEntries.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                    Text("把下方图标拖到这里")
                }.font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 44)
            } else {
                MenuIconStrip(entries: model.shownEntries, model: model, acceptsReordering: true)
                    .padding(.horizontal, 10).frame(height: 44)
            }
        }.padding(.top, 6)
            .background(Color.accentColor.opacity(targeted ? 0.12 : 0))
            .onDrop(of: [.foldBarApplication], isTargeted: $targeted) { model.acceptDrop($0) }
    }
}

/// A horizontal strip with explicit paging when more items exist than fit.
struct MenuIconStrip: View {
    let entries: [MenuEntry]
    @ObservedObject var model: AppModel
    var acceptsReordering = false
    @State private var firstIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let overflow = model.stripWidth(entries) > geometry.size.width
            let step = max(1, Int((geometry.size.width - (overflow ? 44 : 0)) / 44))
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    if overflow { pagingButton("chevron.left", label: "前一组图标", delta: -step, proxy: proxy) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(entries) { entry in
                                if acceptsReordering {
                                    MenuIconButton(entry: entry, model: model)
                                        .onDrop(of: [.foldBarApplication], isTargeted: nil) { model.acceptDrop($0, before: entry) }
                                        .id(entry.id)
                                } else { MenuIconButton(entry: entry, model: model).id(entry.id) }
                            }
                        }.padding(.vertical, 2)
                    }
                    if overflow { pagingButton("chevron.right", label: "后一组图标", delta: step, proxy: proxy) }
                }.frame(height: 44)
                    .onChange(of: entries.map(\.id)) { ids in firstIndex = min(firstIndex, max(0, ids.count - 1)) }
            }
        }.frame(height: 44)
    }

    private func pagingButton(_ symbol: String, label: String, delta: Int, proxy: ScrollViewProxy) -> some View {
        Button {
            firstIndex = min(max(0, firstIndex + delta), max(0, entries.count - 1))
            guard entries.indices.contains(firstIndex) else { return }
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(entries[firstIndex].id, anchor: .leading) }
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 22, height: 40)
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct MenuIconButton: View {
    let entry: MenuEntry
    @ObservedObject var model: AppModel

    var body: some View {
        DraggableMenuIcon(entry: entry, model: model)
            .frame(width: max(20, model.iconSize(entry).width), height: 40)
    }
}
