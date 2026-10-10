import SwiftUI

struct CardRef: Identifiable {
    let id: UUID
}

struct BoardView: View {
    @EnvironmentObject private var store: Store
    let boardID: UUID

    @State private var editingCard: CardRef?
    @State private var showArchive = false
    @State private var showBackground = false
    @State private var search = ""

    var body: some View {
        if let board = store.board(boardID) {
            content(board)
        }
    }

    private func content(_ board: Board) -> some View {
        let archivedCount = board.cards.filter(\.isArchived).count
        return ZStack {
            board.background.color.ignoresSafeArea()
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(board.columns.enumerated()), id: \.element.id) { index, column in
                        ColumnView(
                            boardID: boardID,
                            column: column,
                            cards: visibleCards(board, in: column.id),
                            isFirst: index == 0,
                            isLast: index == board.columns.count - 1,
                            onOpen: { editingCard = CardRef(id: $0.id) }
                        )
                    }
                    AddColumnView(boardID: boardID, background: board.background)
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationTitle(board.name)
        .searchable(text: $search, placement: .toolbar, prompt: "搜索卡片")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showBackground.toggle()
                } label: {
                    Label("背景颜色", systemImage: "paintpalette")
                }
                .help("背景颜色")
                .popover(isPresented: $showBackground, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("看板背景").font(.headline)
                        ColorSwatchPicker(
                            selection: Binding(
                                get: { store.board(boardID)?.background },
                                set: { if let c = $0 { store.setBackground(boardID, c) } }
                            ),
                            allowsNone: false
                        )
                    }
                    .padding(14)
                }

                Button {
                    showArchive = true
                } label: {
                    Label(archivedCount > 0 ? "归档 (\(archivedCount))" : "归档", systemImage: "archivebox")
                        .labelStyle(.titleAndIcon)
                }
                .help("查看已归档的卡片")
            }
        }
        .onAppear(perform: handleOpenRequest)
        .onChange(of: store.openRequest) { _, _ in handleOpenRequest() }
        .sheet(item: $editingCard) { ref in
            if let card = store.card(ref.id, in: boardID) {
                CardEditorView(boardID: boardID, card: card)
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showArchive) {
            ArchiveView(boardID: boardID, onOpen: { card in
                showArchive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editingCard = CardRef(id: card.id) }
            })
            .environmentObject(store)
        }
    }

    private func handleOpenRequest() {
        guard let request = store.openRequest, request.boardID == boardID else { return }
        store.openRequest = nil
        showArchive = false
        editingCard = CardRef(id: request.cardID)
    }

    private func visibleCards(_ board: Board, in columnID: UUID) -> [Card] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return board.cards.filter { card in
            guard card.columnID == columnID, !card.isArchived else { return false }
            guard !query.isEmpty else { return true }
            return card.matches(query)
        }
    }
}

struct AddColumnView: View {
    @EnvironmentObject private var store: Store
    let boardID: UUID
    let background: RGBAColor

    @State private var adding = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if adding {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("输入列表名称", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { cancel() }
                    HStack {
                        Button("添加列表", action: commit)
                            .buttonStyle(.borderedProminent)
                        Button("取消", action: cancel)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
            } else {
                Button {
                    adding = true
                    DispatchQueue.main.async { focused = true }
                } label: {
                    Label("添加列表", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .foregroundStyle(background.foreground)
                        .background(RoundedRectangle(cornerRadius: 12).fill(background.foreground.opacity(0.18)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 272)
    }

    private func commit() {
        store.addColumn(to: boardID, name: name)
        name = ""
        focused = true
    }

    private func cancel() {
        adding = false
        name = ""
    }
}
