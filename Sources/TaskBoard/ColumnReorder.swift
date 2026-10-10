import SwiftUI
import AppKit
import Observation

/// 列表拖动排序。
///
/// 拖动整个列表时，其他列表会实时让位，预览放下后的顺序；松开鼠标后按预览顺序保存（一个撤销步骤）。
/// 拖到看板以外松开或按 Esc 取消时，列表回到原来的位置。
@Observable
final class ColumnReorder {
    /// 正在拖动的列表
    private(set) var draggingID: UUID?
    /// 预览中的顺序；为 nil 时按看板实际顺序显示
    private(set) var previewOrder: [UUID]?

    @ObservationIgnored var animation: Animation? = Motion.move
    @ObservationIgnored private let watcher = DragReleaseWatcher()

    var isDragging: Bool { draggingID != nil }

    func begin(_ id: UUID, order: [UUID]) {
        draggingID = id
        previewOrder = order
        watcher.start { [weak self] in self?.cancel() }
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

    /// 放下：保存预览中的顺序并结束拖动。
    ///
    /// 预览时列表已经移动到位，所以放下时不能再有任何动画：先保存实际顺序（与预览一致，画面不变），
    /// 再清除预览，整个过程关闭动画。如果先清除预览，可能会有一帧显示旧顺序，随后再播放一次交换动画。
    func commit(_ save: ([UUID]) -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let order = previewOrder { save(order) }
            finish(animated: false)
        }
    }

    func cancel() {
        finish(animated: true)
    }

    private func finish(animated: Bool) {
        watcher.stop()
        withAnimation(animated ? animation : nil) {
            draggingID = nil
            previewOrder = nil
        }
    }
}

/// 拖动列表期间覆盖整个看板的放置区域，根据鼠标的横向位置计算目标位置
struct ColumnReorderDropDelegate: DropDelegate {
    let reorder: ColumnReorder
    /// 列表宽度 + 间距
    let slotWidth: CGFloat
    /// 第一个列表左侧的留白
    let leadingInset: CGFloat
    let onCommit: ([UUID]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.taskBoardColumn])
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // 不再根据落点重新计算：放下的位置就是用户最后看到的预览位置
        reorder.commit(onCommit)
        return true
    }

    private func update(_ info: DropInfo) {
        reorder.hover(slot: Int(((info.location.x - leadingInset) / slotWidth).rounded(.down)))
    }
}

/// 拖动列表时跟随鼠标的预览
struct ColumnDragPreview: View {
    let column: BoardColumn
    let cardCount: Int

    var body: some View {
        let foreground = column.color?.foreground ?? .primary
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foreground.opacity(0.6))
            Text(column.name)
                .font(.headline)
                .foregroundStyle(foreground)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(cardCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(foreground.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 272)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(column.color.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
        )
        .rotationEffect(.degrees(-2))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        .padding(12)
    }
}
