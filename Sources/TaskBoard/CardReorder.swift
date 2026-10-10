import SwiftUI
import AppKit
import Observation

/// 看板内容的坐标空间：卡片位置和拖放位置都以它为准
enum BoardSpace {
    static let name = "board"
}

/// SwiftUI 不会通知“拖动在别处结束”（拖到看板外松开、按 Esc），
/// 所以观察鼠标按键：松开一小段时间后仍未放下，就视为取消。
final class DragReleaseWatcher {
    private var timer: Timer?
    private var releasedTicks = 0

    func start(onCancel: @escaping () -> Void) {
        stop()
        releasedTicks = 0
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                self.releasedTicks += 1
                if self.releasedTicks >= 3 { onCancel() }
            } else {
                self.releasedTicks = 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

struct CardDropTarget: Equatable {
    var columnID: UUID
    /// 在目标列表（可见卡片，不含被拖动的卡片）中的位置
    var index: Int
}

/// 卡片拖动排序：拖动时卡片本身实时移动到预览位置，其他卡片让位；松开后直接落在预览位置。
@Observable
final class CardReorder {
    private(set) var draggingID: UUID?
    private(set) var target: CardDropTarget?
    /// 开始拖动时的位置；放回原处时不保存（避免产生无意义的撤销步骤）
    @ObservationIgnored private var origin: CardDropTarget?

    /// 卡片在看板坐标空间中的位置（由卡片视图上报；不触发界面刷新）
    @ObservationIgnored var frames: [UUID: CGRect] = [:]
    @ObservationIgnored var animation: Animation? = Motion.move
    @ObservationIgnored private let watcher = DragReleaseWatcher()

    var isDragging: Bool { draggingID != nil }

    func begin(_ cardID: UUID, at start: CardDropTarget) {
        draggingID = cardID
        target = start
        origin = start
        watcher.start { [weak self] in self?.cancel() }
    }

    func hover(_ newTarget: CardDropTarget) {
        guard isDragging, newTarget != target else { return }
        withAnimation(animation) { target = newTarget }
    }

    /// 放下：先保存（与预览一致，画面不变），再清除预览；整个过程关闭动画，避免再播放一次移动动画
    func commit(_ save: (UUID, CardDropTarget) -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let id = draggingID, let target, target != origin { save(id, target) }
            finish()
        }
    }

    func cancel() {
        withAnimation(animation) { finish() }
    }

    private func finish() {
        watcher.stop()
        draggingID = nil
        target = nil
    }
}

/// 拖动卡片期间覆盖整个看板的放置区域
struct CardReorderDropDelegate: DropDelegate {
    let reorder: CardReorder
    /// 当前显示顺序的列表
    let columnIDs: [UUID]
    /// 每个列表当前显示的卡片（包含预览中的被拖动卡片）
    let cardIDs: (UUID) -> [UUID]
    let slotWidth: CGFloat
    let leadingInset: CGFloat
    let onCommit: (UUID, CardDropTarget) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.taskBoardCard])
    }

    func dropEntered(info: DropInfo) { update(info.location) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        // 不根据落点重新计算：放下的位置就是最后看到的预览位置
        reorder.commit(onCommit)
        return true
    }

    private func update(_ point: CGPoint) {
        guard let dragged = reorder.draggingID, !columnIDs.isEmpty else { return }
        let slot = Int(((point.x - leadingInset) / slotWidth).rounded(.down))
        let columnID = columnIDs[min(max(slot, 0), columnIDs.count - 1)]

        // 鼠标停在被拖动卡片自己的预览位置上：保持不变（避免来回跳动）
        if reorder.target?.columnID == columnID, let own = reorder.frames[dragged], own.contains(point) {
            return
        }

        // 放在第一张中线低于鼠标的卡片前面；都高于鼠标则放到最后
        let others = cardIDs(columnID).filter { $0 != dragged }
        var index = others.count
        for (i, id) in others.enumerated() {
            if let frame = reorder.frames[id], point.y < frame.midY {
                index = i
                break
            }
        }
        reorder.hover(CardDropTarget(columnID: columnID, index: index))
    }
}

/// 拖动卡片时跟随鼠标的预览
struct CardDragPreview: View {
    let card: Card

    var body: some View {
        let foreground = card.color?.foreground ?? .primary
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: card.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(card.isDone ? Color.green : foreground.opacity(0.5))
            Text(card.title)
                .foregroundStyle(foreground)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(width: 250, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(card.color?.color ?? Color(nsColor: .controlBackgroundColor))
        )
        .rotationEffect(.degrees(-2))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        .padding(12)
    }
}
