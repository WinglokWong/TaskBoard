import SwiftUI

private struct UpcomingRef: Identifiable {
    let boardID: UUID
    let cardID: UUID
    var id: UUID { cardID }
}

private struct UpcomingItem: Identifiable {
    let board: Board
    let card: Card
    var id: UUID { card.id }
}

/// 汇总所有看板中有截止日期的卡片
struct UpcomingView: View {
    @Environment(Store.self) private var store
    @State private var editing: UpcomingRef?
    @State private var showDone = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let sections = sections(now: context.date)
            if sections.isEmpty {
                let hiddenDone = completedWithDueDateCount
                ContentUnavailableView {
                    Label("没有待完成的到期卡片", systemImage: "calendar.badge.clock")
                } description: {
                    if hiddenDone > 0 {
                        Text("有 \(hiddenDone) 张已完成的卡片设置了截止日期，已被隐藏。")
                    } else {
                        Text("给卡片设置截止日期后，未完成的卡片会在这里按时间汇总显示。")
                    }
                } actions: {
                    if hiddenDone > 0 {
                        Button("显示已完成的卡片") { showDone = true }
                    }
                }
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.items) { row($0) }
                        } header: {
                            HStack {
                                Text(section.title)
                                Text("\(section.items.count)").foregroundStyle(.secondary)
                            }
                            .foregroundStyle(section.title == DueCategory.overdue.title ? Color.red : Color.primary)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("即将到期")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showDone) {
                    Label("显示已完成", systemImage: "checkmark.circle")
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
            }
        }
        .sheet(item: $editing) { ref in
            if let card = store.card(ref.cardID, in: ref.boardID) {
                CardEditorView(boardID: ref.boardID, card: card)
                    .environment(store)
            }
        }
    }

    private var completedWithDueDateCount: Int {
        store.data.boards.reduce(0) { total, board in
            total + board.cards.filter { $0.isDone && !$0.isArchived && $0.dueDate != nil }.count
        }
    }

    private func sections(now: Date) -> [(title: String, items: [UpcomingItem])] {
        var open: [DueCategory: [UpcomingItem]] = [:]
        var done: [UpcomingItem] = []
        for board in store.data.boards {
            for card in board.cards where !card.isArchived {
                guard let due = card.dueDate else { continue }
                let item = UpcomingItem(board: board, card: card)
                if card.isDone {
                    if showDone { done.append(item) }
                } else {
                    open[DueCategory.of(due, now: now), default: []].append(item)
                }
            }
        }
        let byDate: (UpcomingItem, UpcomingItem) -> Bool = { ($0.card.dueDate ?? .distantFuture) < ($1.card.dueDate ?? .distantFuture) }
        var result = DueCategory.allCases.compactMap { category -> (String, [UpcomingItem])? in
            guard let items = open[category], !items.isEmpty else { return nil }
            return (category.title, items.sorted(by: byDate))
        }
        if !done.isEmpty { result.append(("已完成", done.sorted(by: byDate))) }
        return result
    }

    private func row(_ item: UpcomingItem) -> some View {
        let card = item.card, board = item.board
        return HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { store.toggleDone(card.id, in: board.id) }
            } label: {
                Image(systemName: card.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(card.isDone ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .help(card.isDone ? "标记为未完成" : "标记为已完成")

            RoundedRectangle(cornerRadius: 2)
                .fill(card.color?.color ?? Color.secondary.opacity(0.25))
                .frame(width: 4, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .strikethrough(card.isDone)
                    .foregroundStyle(card.isDone ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(board.background.color)
                        .frame(width: 10, height: 10)
                    Text("\(board.name) · \(board.columnName(card.columnID) ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(board.labels(of: card)) { LabelPill(label: $0) }
                }
            }
            Spacer()
            if let due = card.dueDate {
                DueBadge(date: due, isDone: card.isDone, reminder: card.reminderMinutes != nil)
                    .font(.caption)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { editing = UpcomingRef(boardID: board.id, cardID: card.id) }
        .contextMenu {
            Button("打开") { editing = UpcomingRef(boardID: board.id, cardID: card.id) }
            Button("前往看板") {
                store.showingUpcoming = false
                store.data.selectedBoardID = board.id
            }
        }
    }
}
