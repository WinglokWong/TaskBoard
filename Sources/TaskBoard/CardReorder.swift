import SwiftUI
import Observation

/// 看板内容的坐标空间：卡片 / 列表的位置和拖动时的鼠标位置都以它为准
enum BoardSpace {
    static let name = "board"
    /// 列表宽度 + 间距
    static let slotWidth: CGFloat = 272 + 12
    /// 第一个列表左侧的留白
    static let leadingInset: CGFloat = 16

    /// 鼠标横坐标对应的列表位置
    static func slot(atX x: CGFloat) -> Int {
        Int(((x - leadingInset) / slotWidth).rounded(.down))
    }
}

struct CardDropTarget: Equatable {
    var columnID: UUID
    /// 在目标列表（可见卡片，不含被拖动的卡片）中的位置
    var index: Int
}

/// 卡片拖动的预览位置：被拖动的卡片实时移动到预览位置，其他卡片让位
@Observable
final class CardReorder {
    private(set) var draggingID: UUID?
    private(set) var target: CardDropTarget?

    /// 卡片在看板坐标空间中的位置（由卡片视图上报；不触发界面刷新）
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    /// 各列表中预览占位的位置（按列表分开记录）。
    /// 占位从一个列表移到另一个列表时，旧占位在淡出过程中仍可能上报位置；
    /// 按列表分开记录，旧列表的上报就不会覆盖目标列表的位置。
    @ObservationIgnored var placeholderFrames: [UUID: CGRect] = [:]

    /// 当前目标列表中占位的位置
    var placeholderFrame: CGRect? {
        target.flatMap { placeholderFrames[$0.columnID] }
    }
    @ObservationIgnored var animation: Animation? = Motion.move
    /// 开始拖动时的位置；放回原处时不保存（避免产生无意义的撤销步骤）
    @ObservationIgnored private var origin: CardDropTarget?

    var isDragging: Bool { draggingID != nil }

    func begin(_ cardID: UUID, at start: CardDropTarget) {
        draggingID = cardID
        target = start
        origin = start
    }

    func hover(_ newTarget: CardDropTarget) {
        guard isDragging, newTarget != target else { return }
        // 预览位置变了：旧的占位位置作废，等占位在新位置完成布局后重新上报
        placeholderFrames[newTarget.columnID] = nil
        withAnimation(animation) { target = newTarget }
    }

    /// 取消：占位回到原来的位置
    func revert() {
        guard let origin else { return }
        placeholderFrames[origin.columnID] = nil
        withAnimation(animation) { target = origin }
    }

    /// 保存预览位置（在浮动副本落下之后调用，此时画面已与预览一致）
    func commit(_ save: (UUID, CardDropTarget) -> Void) {
        if let id = draggingID, let target, target != origin { save(id, target) }
        finish()
    }

    func finish() {
        draggingID = nil
        target = nil
        origin = nil
        placeholderFrames = [:]
    }

    /// 鼠标位置对应的放置位置；返回 nil 表示保持不变
    func target(at point: CGPoint, columnIDs: [UUID], cardIDs: (UUID) -> [UUID]) -> CardDropTarget? {
        guard let dragged = draggingID, !columnIDs.isEmpty else { return nil }
        let columnID = columnIDs[min(max(BoardSpace.slot(atX: point.x), 0), columnIDs.count - 1)]

        // 鼠标停在被拖动卡片自己的预览位置上：保持不变（避免来回跳动）
        if target?.columnID == columnID, let own = placeholderFrame, own.contains(point) {
            return nil
        }

        // 放在第一张中线低于鼠标的卡片前面；都高于鼠标则放到最后
        let others = cardIDs(columnID).filter { $0 != dragged }
        var index = others.count
        for (i, id) in others.enumerated() {
            if let frame = frames[id], point.y < frame.midY {
                index = i
                break
            }
        }
        return CardDropTarget(columnID: columnID, index: index)
    }
}
