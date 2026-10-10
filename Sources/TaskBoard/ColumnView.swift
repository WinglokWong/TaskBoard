import SwiftUI

struct ColumnView: View {
    @EnvironmentObject private var store: Store
    let boardID: UUID
    let column: BoardColumn
    let cards: [Card]
    let isFirst: Bool
    let isLast: Bool
    var selectedCardID: UUID? = nil
    /// 键盘快捷键 N 请求在这一列添加卡片
    @Binding var addRequest: UUID?
    var onOpen: (Card) -> Void
    var onHoverCard: (UUID, Bool) -> Void = { _, _ in }

    @State private var isRenaming = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    @State private var addingCard = false
    @State private var newTitle = ""
    @FocusState private var newCardFocused: Bool

    @State private var showColor = false
    @State private var confirmDelete = false
    @State private var dropTargeted = false
    @State private var contentHeight: CGFloat = 0

    private var foreground: Color { column.color?.foreground ?? .primary }

    private var background: AnyShapeStyle {
        if let color = column.color { return AnyShapeStyle(color.color) }
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(0.94))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        CardView(boardID: boardID, card: card, isSelected: card.id == selectedCardID,
                                 onOpen: { onOpen(card) },
                                 onHover: { onHoverCard(card.id, $0) })
                        .id(card.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { contentHeight = g.size.height }
                        .onChange(of: g.size.height) { _, height in contentHeight = height }
                })
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: max(contentHeight, 1))
            footer
        }
        .padding(10)
        .frame(width: 272)
        .background(RoundedRectangle(cornerRadius: 12).fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 2 : 0)
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.compactMap(CardDrag.decode).first else { return false }
            store.moveCard(id, in: boardID, to: column.id, before: nil)
            return true
        } isTargeted: { dropTargeted = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: addRequest) { _, request in
            guard request == column.id else { return }
            addRequest = nil
            startAdding()
        }
        .confirmationDialog("确定删除列表「\(column.name)」吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除列表", role: .destructive) { store.deleteColumn(column.id, in: boardID) }
        } message: {
            Text("列表中的卡片会被移入归档，可以稍后恢复。")
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 6) {
            if isRenaming {
                TextField("列表名称", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused && isRenaming { commitRename() }
                    }
            } else {
                Text(column.name)
                    .font(.headline)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .onTapGesture(count: 2, perform: beginRename)
                    .help("双击重命名")
                Text("\(cards.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(foreground.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(foreground.opacity(0.1)))
            }
            Spacer(minLength: 4)

            Button { showColor.toggle() } label: {
                Image(systemName: "paintpalette").foregroundStyle(foreground.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("列表颜色")
            .popover(isPresented: $showColor, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("列表颜色").font(.headline)
                    ColorSwatchPicker(selection: Binding(
                        get: { column.color },
                        set: { store.setColumnColor(column.id, in: boardID, $0) }
                    ))
                }
                .padding(14)
            }

            Menu {
                Button("重命名", action: beginRename)
                Button("添加卡片") { startAdding() }
                Divider()
                Button("向左移动") { store.moveColumn(column.id, in: boardID, by: -1) }
                    .disabled(isFirst)
                Button("向右移动") { store.moveColumn(column.id, in: boardID, by: 1) }
                    .disabled(isLast)
                Divider()
                Button("归档本列已完成的卡片") { store.archiveCards(in: column.id, of: boardID, onlyDone: true) }
                Button("归档本列全部卡片") { store.archiveCards(in: column.id, of: boardID, onlyDone: false) }
                Divider()
                Button("删除列表…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(foreground.opacity(0.75))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 24)
    }

    // MARK: - 底部

    @ViewBuilder
    private var footer: some View {
        if addingCard {
            VStack(alignment: .leading, spacing: 8) {
                TextField("输入卡片标题，回车添加", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($newCardFocused)
                    .onSubmit(commitNewCard)
                    .onExitCommand(perform: cancelAdding)
                HStack {
                    Button("添加卡片", action: commitNewCard)
                        .buttonStyle(.borderedProminent)
                    Button(action: cancelAdding) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(foreground)
                }
            }
        } else {
            Button(action: startAdding) {
                Label("添加卡片", systemImage: "plus")
                    .foregroundStyle(foreground.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle(tint: foreground))
        }
    }

    // MARK: - 操作

    private func beginRename() {
        nameDraft = column.name
        isRenaming = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitRename() {
        store.renameColumn(column.id, in: boardID, to: nameDraft)
        isRenaming = false
    }

    private func startAdding() {
        addingCard = true
        DispatchQueue.main.async { newCardFocused = true }
    }

    private func commitNewCard() {
        store.addCard(to: column.id, in: boardID, title: newTitle)
        newTitle = ""
        newCardFocused = true
    }

    private func cancelAdding() {
        addingCard = false
        newTitle = ""
    }
}

struct HoverButtonStyle: ButtonStyle {
    var tint: Color = .primary
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(configuration.isPressed ? 0.15 : (hovering ? 0.08 : 0)))
            )
            .onHover { hovering = $0 }
    }
}
