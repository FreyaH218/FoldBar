import SwiftUI

struct PinnedShelfView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("显示区", systemImage: "menubar.rectangle").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("对应顶部真实图标的顺序").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if model.shownEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.up.to.line.compact").font(.system(size: 22))
                    Text(targeted ? "松开，将原图标移到顶部" : "把下方图标拖到这里显示")
                        .font(.system(size: 12))
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 64)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(model.shownEntries) { entry in
                            VStack(spacing: 4) {
                                Image(nsImage: entry.icon).resizable().frame(width: 27, height: 27)
                                Text(entry.name).font(.system(size: 10)).lineLimit(1).frame(width: 62)
                            }
                            .frame(width: 66, height: 62)
                            .contentShape(Rectangle())
                            .onDrag { model.dragProvider(for: entry) }
                            .onDrop(of: [.foldBarApplication], isTargeted: nil) { model.acceptDrop($0, before: entry) }
                            .contextMenu { Button("收回隐藏区") { model.onHideEntry(entry) } }
                            .accessibilityLabel("顶部原图标：\(entry.name)")
                        }
                        Image(systemName: "plus").frame(width: 30, height: 60).foregroundStyle(.secondary)
                    }
                }.frame(height: 76)
            }
            HStack(alignment: .top) {
                if model.applyingNativeLayout { ProgressView().controlSize(.small) }
                Text(model.nativeLayoutStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(targeted ? 0.13 : 0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(targeted ? 0.8 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
        .onDrop(of: [.foldBarApplication], isTargeted: $targeted) { model.acceptDrop($0) }
    }
}
