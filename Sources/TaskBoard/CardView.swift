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
    var onBeginDrag: () -> Void = {}

    static func == (a: CardView, b: CardView) -> Bool {
        a.boardID == b.boardID && a.card == b.card && a.labels == b.labels && a.isSelected == b.isSelected
            && a.isDragPlaceholder == b.isDragPlaceholder && a.boardLabels == b.boardLabels && a.columns == b.columns
    }

    @State private var hovering = false
    @State private var confirmDelete = false

    private var foreground: Color { card.color?.foreground ?? .primary }

    private var hasBadges: Bool {
        card.dueDate != nil || !card.checklist.isEmpty || !card.details.isEmpty || !card.attachments.isEmpty
    }

    private var background: Color {
        card.color?.color ?? Color(nsColor: .controlBackgroundColor)
    }

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
        // 卡片的放置由看板统一处理（见 CardReorder），这里只负责开始拖动
        .onDrag {
            onBeginDrag()
            let provider = NSItemProvider()
            provider.register(CardDragItem(id: card.id))
            return provider
        } preview: {
            CardDragPreview(card: card)
        }
        .contextMenu { contextMenu }
        .confirmationDialog("确定删除卡片「\(card.title)」吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.deleteCard(card.id, in: boardID) }
        } message: {
            Text("可以用 ⌘Z 撤销。如果只是暂时不需要，也可以选择归档。")
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !labels.isEmpty {
                LabelRow(labels: labels)
            }
            if let cover = card.coverImage {
                AttachmentThumbnail(attachment: cover)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    withAnimation(.snappy) { store.toggleDone(card.id, in: boardID) }
                } label: {
                    Image(systemName: card.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(card.isDone ? Color.green : foreground.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(card.isDone ? "标记为未完成" : "标记为已完成")

                Text(card.title)
                    .font(.body)
                    .strikethrough(card.isDone)
                    .foregroundStyle(foreground.opacity(card.isDone ? 0.55 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }

            if hasBadges {
                HStack(spacing: 10) {
                    if let due = card.dueDate {
                        DueBadge(date: due, isDone: card.isDone, reminder: card.reminderMinutes != nil, foreground: foreground)
                    }
                    if !card.checklist.isEmpty {
                        let done = card.checklistDoneCount, total = card.checklist.count
                        Label("\(done)/\(total)", systemImage: "checklist")
                            .padding(.horizontal, done == total ? 5 : 0)
                            .padding(.vertical, done == total ? 1 : 0)
                            .background(Capsule().fill(done == total ? Color.green : Color.clear))
                            .foregroundStyle(done == total ? Color.white : foreground.opacity(0.6))
                            .help("清单进度")
                    }
                    if !card.details.isEmpty {
                        Image(systemName: "text.alignleft").help("有描述")
                    }
                    if !card.attachments.isEmpty {
                        Label("\(card.attachments.count)", systemImage: "paperclip")
                    }
                }
                .font(.caption)
                .foregroundStyle(foreground.opacity(0.6))
                .padding(.leading, 23)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : (hovering ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.06)),
                              lineWidth: isSelected ? 2 : (hovering ? 1.5 : 1))
        )
        // 悬停时轻微抬起
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.12), radius: hovering ? 4 : 1, y: hovering ? 2 : 1)
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: isSelected)
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

/// 截止日期徽章：已完成为绿色，已过期为红色，24 小时内到期为橙色
struct DueBadge: View {
    let date: Date
    let isDone: Bool
    var reminder = false
    var foreground: Color = .primary

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let style = style(now: context.date)
            Label(DueFormat.short(date, now: context.date), systemImage: reminder ? "bell" : "clock")
                .padding(.horizontal, style.filled ? 5 : 0)
                .padding(.vertical, style.filled ? 1 : 0)
                .background(Capsule().fill(style.fill))
                .foregroundStyle(style.filled ? Color.white : foreground.opacity(0.6))
                .help(style.help)
        }
    }

    private func style(now: Date) -> (fill: Color, filled: Bool, help: String) {
        if isDone { return (.green, true, String(localized: "已完成")) }
        if date < now { return (.red, true, String(localized: "已过期")) }
        if date.timeIntervalSince(now) < 24 * 3600 { return (.orange, true, String(localized: "即将到期")) }
        return (.clear, false, String(localized: "截止日期"))
    }
}
