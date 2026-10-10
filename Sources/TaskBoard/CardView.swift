import SwiftUI

/// 卡片。所有显示所需的数据都通过参数传入、不在 body 中读取 store，
/// 配合 `.equatable()` 使用时，只有这张卡片的数据变化才会重绘。
struct CardView: View, Equatable {
    @Environment(Store.self) private var store
    let boardID: UUID
    let card: Card
    /// 这张卡片上的标签
    let labels: [CardLabel]
    /// 看板全部标签与列表（用于右键菜单）
    let boardLabels: [CardLabel]
    let columns: [BoardColumn]
    var isSelected = false
    /// 正在被拖动：在预览位置显示为半透明占位
    var isDragPlaceholder = false
    var onOpen: () -> Void
    var onHover: (Bool) -> Void = { _ in }

    static func == (a: CardView, b: CardView) -> Bool {
        a.boardID == b.boardID && a.card == b.card && a.labels == b.labels && a.isSelected == b.isSelected
            && a.isDragPlaceholder == b.isDragPlaceholder && a.boardLabels == b.boardLabels && a.columns == b.columns
    }

    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        cardBody
            .opacity(isDragPlaceholder ? 0.35 : 1)
            .overlay {
                if isDragPlaceholder {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
        .onTapGesture(perform: onOpen)
        // 拖动由看板统一处理（见 BoardView 的看板级拖动手势和 BoardDrag）
        .contextMenu { contextMenu }
        .confirmationDialog("确定删除卡片「\(card.title)」吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.deleteCard(card.id, in: boardID) }
        } message: {
            Text("可以用 ⌘Z 撤销。如果只是暂时不需要，也可以选择归档。")
        }
    }

    private var cardBody: some View {
        CardFace(card: card, labels: labels, isSelected: isSelected, hovering: hovering) {
            withAnimation(.snappy) { store.toggleDone(card.id, in: boardID) }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("打开", action: onOpen)
        Button(card.isDone ? "标记为未完成" : "标记为已完成") { store.toggleDone(card.id, in: boardID) }
        Menu("颜色") {
            Button("默认") { store.setCardColor(card.id, in: boardID, nil) }
            Divider()
            ForEach(Palette.presets) { preset in
                Button(preset.name) { store.setCardColor(card.id, in: boardID, preset.value) }
            }
        }
        if !boardLabels.isEmpty {
            Menu("标签") {
                ForEach(boardLabels) { label in
                    Toggle(label.displayName, isOn: Binding(
                        get: { card.labelIDs.contains(label.id) },
                        set: { _ in store.toggleLabel(label.id, on: card.id, in: boardID) }
                    ))
                }
            }
        }
        if columns.count > 1 {
            Menu("移动到") {
                ForEach(columns.filter { $0.id != card.columnID }) { column in
                    Button(column.name) { store.moveCard(card.id, in: boardID, to: column.id, before: nil) }
                }
            }
        }
        Divider()
        Button("归档") { store.archiveCard(card.id, in: boardID) }
        Button("删除…", role: .destructive) { confirmDelete = true }
    }
}
