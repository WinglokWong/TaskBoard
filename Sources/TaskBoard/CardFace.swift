import SwiftUI

/// 卡片的外观（不含交互逻辑）。看板上的卡片和拖动时的预览都使用它，保证拖动时看到的就是卡片本身。
struct CardFace: View {
    /// 列表中卡片的宽度：列表宽 272，减去列表内边距 10×2 和卡片区域边距 2×2
    static let width: CGFloat = 272 - 20 - 4

    let card: Card
    let labels: [CardLabel]
    var isSelected = false
    var hovering = false
    /// 为 nil 时（例如拖动预览）完成按钮只显示、不可点击
    var onToggleDone: (() -> Void)? = nil

    private var foreground: Color { card.color?.foreground ?? .primary }

    private var background: Color {
        card.color?.color ?? Color(nsColor: .controlBackgroundColor)
    }

    private var hasBadges: Bool {
        card.dueDate != nil || !card.checklist.isEmpty || !card.details.isEmpty || !card.attachments.isEmpty
    }

    private var doneIcon: some View {
        Image(systemName: card.isDone ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15))
            .foregroundStyle(card.isDone ? Color.green : foreground.opacity(0.5))
    }

    var body: some View {
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
                if let onToggleDone {
                    Button(action: onToggleDone) { doneIcon }
                        .buttonStyle(.plain)
                        .help(card.isDone ? "标记为未完成" : "标记为已完成")
                } else {
                    doneIcon
                }

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
