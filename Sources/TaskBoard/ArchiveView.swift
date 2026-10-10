import SwiftUI

struct ArchiveView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let boardID: UUID
    var onOpen: (Card) -> Void

    @State private var search = ""
    @State private var deletingCard: Card?
    @State private var confirmClear = false

    private var board: Board? { store.board(boardID) }

    private var archived: [Card] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return (board?.cards ?? [])
            .filter(\.isArchived)
            .filter { query.isEmpty || $0.matches(query) }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("已归档的卡片", systemImage: "archivebox")
                    .font(.title3.bold())
                Spacer()
                TextField("搜索归档", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(16)

            Divider()

            if archived.isEmpty {
                ContentUnavailableView(search.isEmpty ? "没有归档的卡片" : "没有匹配的卡片",
                                       systemImage: "archivebox",
                                       description: Text("右键卡片或在卡片详情中选择“归档”"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(archived) { card in
                        row(card)
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button("清空归档…", role: .destructive) { confirmClear = true }
                    .disabled(board?.cards.contains(where: \.isArchived) != true)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 560)
        .confirmationDialog(
            "确定永久删除「\(deletingCard?.title ?? "")」吗？",
            isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let card = deletingCard { store.deleteCard(card.id, in: boardID) }
            }
        }
        .confirmationDialog("确定清空所有归档卡片吗？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("全部删除", role: .destructive) { store.deleteArchivedCards(in: boardID) }
        } message: {
            Text("所有归档卡片及其附件将被永久删除。")
        }
    }

    private func row(_ card: Card) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(card.color?.color ?? Color.secondary.opacity(0.3))
                .frame(width: 6, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if card.isDone {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Text(card.title)
                        .lineLimit(1)
                }
                Text(subtitle(card))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.restoreCard(card.id, in: boardID)
            } label: {
                Label("恢复", systemImage: "arrow.uturn.backward")
            }
            .controlSize(.small)
            Button {
                deletingCard = card
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .help("永久删除")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen(card) }
    }

    private func subtitle(_ card: Card) -> String {
        let column = board?.columnName(card.columnID) ?? String(localized: "已删除的列表")
        let date = card.archivedAt?.appFormatted(date: .abbreviated, time: .shortened) ?? "-"
        return String(localized: "来自「\(column)」· 归档于 \(date)")
    }
}
