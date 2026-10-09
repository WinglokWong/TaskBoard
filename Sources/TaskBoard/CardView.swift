import SwiftUI

struct CardView: View {
    @EnvironmentObject private var store: Store
    let boardID: UUID
    let card: Card
    var onOpen: () -> Void

    @State private var dropTargeted = false
    @State private var hovering = false
    @State private var confirmDelete = false

    private var foreground: Color { card.color?.foreground ?? .primary }

    private var background: Color {
        card.color?.color ?? Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cover = card.coverImage, let image = ImageCache.shared.thumbnail(for: cover) {
                Color.clear
                    .frame(height: 130)
                    .overlay(Image(nsImage: image).resizable().scaledToFill())
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

            if !card.details.isEmpty || !card.attachments.isEmpty {
                HStack(spacing: 10) {
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
                .strokeBorder(hovering ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.06), lineWidth: hovering ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        .overlay(alignment: .top) {
            if dropTargeted {
                Capsule().fill(Color.accentColor).frame(height: 3).offset(y: -6)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .draggable(CardDrag.encode(card.id)) {
            Text(card.title)
                .padding(10)
                .frame(width: 240, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(background))
                .foregroundStyle(foreground)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(CardDrag.decode).first, let columnID = card.columnID else { return false }
            store.moveCard(id, in: boardID, to: columnID, before: card.id)
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu { contextMenu }
        .confirmationDialog("确定删除卡片「\(card.title)」吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { store.deleteCard(card.id, in: boardID) }
        } message: {
            Text("此操作无法撤销。如果只是暂时不需要，可以选择归档。")
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
        if let board = store.board(boardID), board.columns.count > 1 {
            Menu("移动到") {
                ForEach(board.columns.filter { $0.id != card.columnID }) { column in
                    Button(column.name) { store.moveCard(card.id, in: boardID, to: column.id, before: nil) }
                }
            }
        }
        Divider()
        Button("归档") { store.archiveCard(card.id, in: boardID) }
        Button("删除…", role: .destructive) { confirmDelete = true }
    }
}
