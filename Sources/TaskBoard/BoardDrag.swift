import SwiftUI
import Observation

/// 看板上的拖动（卡片或列表）由应用自己绘制，而不是使用系统的拖放图像。
///
/// 这样整个过程都由我们控制：
/// 1. 拿起：在原位置生成一个与原物一模一样的浮动副本，轻微放大并加深阴影；
/// 2. 拖动：副本精确跟随鼠标（保持按下时的相对位置），原位置显示半透明占位并实时预览新顺序；
/// 3. 放下：副本从鼠标处滑入占位的位置并落下，动画结束后才换成真正的卡片 / 列表——不会出现两个副本，也不会跳动；
/// 4. 取消（Esc 或拖到看板外）：副本滑回原来的位置。
@Observable
final class BoardDrag {
    enum Item: Equatable {
        case card(UUID)
        case column(UUID)
    }

    private(set) var item: Item?
    /// 浮动副本在看板坐标空间中的位置和大小
    private(set) var frame: CGRect = .zero
    /// 拿起状态：放大、加深阴影
    private(set) var lifted = false
    /// 正在滑入 / 滑回目标位置
    private(set) var isLanding = false

    /// 已取消（按了 Esc）：忽略后续的鼠标移动，等待松开
    @ObservationIgnored private(set) var cancelled = false
    /// 拿起时的位置，用于取消时滑回
    @ObservationIgnored private(set) var originFrame: CGRect = .zero
    @ObservationIgnored private var grabOffset: CGSize = .zero

    var isActive: Bool { item != nil }

    func isDragging(_ item: Item) -> Bool { self.item == item && !isLanding }

    func begin(_ item: Item, frame: CGRect, pointer: CGPoint, liftAnimation: Animation?) {
        self.item = item
        self.frame = frame
        originFrame = frame
        grabOffset = CGSize(width: pointer.x - frame.minX, height: pointer.y - frame.minY)
        cancelled = false
        isLanding = false
        withAnimation(liftAnimation) { lifted = true }
    }

    /// 跟随鼠标（不加动画，保证紧贴鼠标）
    func move(to pointer: CGPoint) {
        guard isActive, !isLanding, !cancelled else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            frame.origin = CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
        }
    }

    func markCancelled() { cancelled = true }

    /// 滑入目标位置并落下；动画结束后调用 `completion`（保存数据），并在同一时刻移除浮动副本
    func land(at target: CGRect, animation: Animation, completion: @escaping () -> Void) {
        guard isActive, !isLanding else { return }
        isLanding = true
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            frame = target
            lifted = false
        } completion: { [weak self] in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                completion()
                self?.item = nil
                self?.isLanding = false
            }
        }
    }
}

/// 浮动副本：与看板上的卡片 / 列表外观完全相同
struct BoardDragOverlay: View {
    let drag: BoardDrag
    let board: Board
    /// 列表中当前显示的卡片
    let cardsInColumn: (UUID) -> [Card]
    var reduceMotion = false

    var body: some View {
        if let item = drag.item {
            content(for: item)
                .frame(width: drag.frame.width, height: drag.frame.height, alignment: .top)
                .scaleEffect(drag.lifted && !reduceMotion ? 1.03 : 1)
                .shadow(color: .black.opacity(drag.lifted ? 0.25 : 0.08),
                        radius: drag.lifted ? 14 : 2, y: drag.lifted ? 10 : 1)
                .offset(x: drag.frame.minX, y: drag.frame.minY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func content(for item: BoardDrag.Item) -> some View {
        switch item {
        case .card(let id):
            if let card = board.cards.first(where: { $0.id == id }) {
                CardFace(card: card, labels: board.labels(of: card))
            }
        case .column(let id):
            if let column = board.columns.first(where: { $0.id == id }) {
                ColumnFace(column: column, cards: cardsInColumn(id), boardLabels: board.labels,
                           maxHeight: max(drag.frame.height, 60))
            }
        }
    }
}
