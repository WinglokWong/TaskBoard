import SwiftUI
import AppKit
import Observation

/// 列表拖动的预览顺序：拖动整个列表时，其他列表实时让位
@Observable
final class ColumnReorder {
    /// 正在拖动的列表
    private(set) var draggingID: UUID?
    /// 预览中的顺序；为 nil 时按看板实际顺序显示
    private(set) var previewOrder: [UUID]?

    /// 列表在看板坐标空间中的位置（不触发界面刷新）
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    @ObservationIgnored var animation: Animation? = Motion.move
    @ObservationIgnored private var originalOrder: [UUID] = []

    var isDragging: Bool { draggingID != nil }

    func begin(_ id: UUID, order: [UUID]) {
        draggingID = id
        previewOrder = order
        originalOrder = order
    }

    /// 鼠标经过第 `slot` 个列表的位置
    func hover(slot: Int) {
        guard let id = draggingID, var order = previewOrder, let from = order.firstIndex(of: id) else { return }
        let to = min(max(slot, 0), order.count - 1)
        guard to != from else { return }
        order.remove(at: from)
        order.insert(id, at: to)
        withAnimation(animation) { previewOrder = order }
    }

    /// 取消：恢复原来的顺序
    func revert() {
        guard isDragging else { return }
        withAnimation(animation) { previewOrder = originalOrder }
    }

    /// 保存预览顺序（在浮动副本落下之后调用）
    func commit(_ save: ([UUID]) -> Void) {
        if let order = previewOrder, order != originalOrder { save(order) }
        finish()
    }

    func finish() {
        draggingID = nil
        previewOrder = nil
        originalOrder = []
    }
}

/// 拖动列表时跟随鼠标的预览：列表本来的样子（标题、卡片、底部），不倾斜
struct ColumnFace: View {
    let column: BoardColumn
    let cards: [Card]
    let boardLabels: [CardLabel]
    /// 很长的列表在预览中截断，底部渐隐
    var maxHeight: CGFloat = 600

    private var foreground: Color { column.color?.foreground ?? .primary }

    private var background: AnyShapeStyle {
        if let color = column.color { return AnyShapeStyle(color.color) }
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(0.94))
    }

    var body: some View {
        // 能完整放下就显示整个列表；放不下时截断到最大高度，底部渐隐
        ViewThatFits(in: .vertical) {
            content
            content
                .frame(height: maxHeight, alignment: .top)
                .clipped()
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 56)
                    }
                }
        }
        .frame(maxHeight: maxHeight)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 与 ColumnView 的标题行一致
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(foreground.opacity(0.7))
                    .frame(width: 14, height: 20)
                Text(column.name)
                    .font(.headline)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                Text("\(cards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(foreground.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(foreground.opacity(0.1)))
                Spacer(minLength: 4)
                Image(systemName: "paintpalette").foregroundStyle(foreground.opacity(0.75))
                Image(systemName: "ellipsis").foregroundStyle(foreground.opacity(0.75))
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 24)

            VStack(spacing: 8) {
                ForEach(cards) { card in
                    CardFace(card: card, labels: boardLabels.filter { card.labelIDs.contains($0.id) })
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)

            Label("添加卡片", systemImage: "plus")
                .foregroundStyle(foreground.opacity(0.8))
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
        }
        .padding(10)
        .frame(width: 272, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 12).fill(background))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
