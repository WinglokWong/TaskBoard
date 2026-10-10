import SwiftUI

struct ColumnView: View {
    @Environment(Store.self) private var store
    let boardID: UUID
    let column: BoardColumn
    let cards: [Card]
    let isFirst: Bool
    let isLast: Bool
    /// 看板的全部标签与列表（传给卡片，用于显示和右键菜单）
    let boardLabels: [CardLabel]
    let columns: [BoardColumn]
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropIndicator: ColumnDropIndicator?
    @State private var headerHovering = false
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
                        CardView(boardID: boardID, card: card,
                                 labels: boardLabels.filter { card.labelIDs.contains($0.id) },
                                 boardLabels: boardLabels, columns: columns,
                                 isSelected: card.id == selectedCardID,
                                 onOpen: { onOpen(card) },
                                 onHover: { onHoverCard(card.id, $0) })
                        .equatable()
                        .id(card.id)
                        .transition(Motion.cardTransition(reduceMotion))
                    }
                }
                // 卡片移动、增删、筛选时平滑过渡
                .animation(Motion.move(reduceMotion), value: cards.map(\.id))
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
                .strokeBorder(Color.accentColor, lineWidth: dropIndicator == .card ? 2 : 0)
        )
        .overlay(alignment: dropIndicator == .after ? .trailing : .leading) {
            // 拖动列表经过时，在左侧或右侧显示插入位置
            if dropIndicator == .before || dropIndicator == .after {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 4)
                    .offset(x: dropIndicator == .after ? 9 : -9)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .shadow(color: .black.opacity(dropIndicator == .card ? 0.2 : 0.12), radius: dropIndicator == .card ? 6 : 2, y: 1)
        // 列表经过时向另一侧让出空位
        .offset(x: reduceMotion ? 0 : (dropIndicator == .before ? 8 : dropIndicator == .after ? -8 : 0))
        .animation(Motion.gap(reduceMotion), value: dropIndicator)
        .onDrop(of: [.taskBoardCard, .taskBoardColumn], delegate: ColumnDropDelegate(
            columnID: column.id,
            width: 272,
            indicator: $dropIndicator,
            onCard: { store.moveCard($0, in: boardID, to: column.id, before: nil) },
            onColumn: { store.moveColumn($0, in: boardID, to: column.id, after: $1) }
        ))
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
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(foreground.opacity(headerHovering ? 0.7 : 0.3))
                    .frame(width: 14, height: 20)
                    .contentShape(Rectangle())
                    .help("拖动调整列表顺序")
                    .draggable(ColumnDragItem(id: column.id)) { dragPreview }
                Text(column.name)
                    .font(.headline)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    // 用 simultaneousGesture，双击重命名不会阻止拖动
                    .simultaneousGesture(TapGesture(count: 2).onEnded(beginRename))
                    .help("双击重命名，拖动调整顺序")
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
        .contentShape(Rectangle())
        .onHover { headerHovering = $0 }
        .draggable(ColumnDragItem(id: column.id)) { dragPreview }
    }

    private var dragPreview: some View {
        Text(column.name)
            .font(.headline)
            .padding(10)
            .frame(width: 240, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(background))
            .foregroundStyle(foreground)
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

enum ColumnDropIndicator {
    /// 卡片将放入这一列
    case card
    /// 列表将放到这一列的前面 / 后面
    case before, after
}

/// 列表的放置处理：卡片放到列表末尾；列表根据落点在左半边还是右半边，放到前面或后面
struct ColumnDropDelegate: DropDelegate {
    let columnID: UUID
    let width: CGFloat
    @Binding var indicator: ColumnDropIndicator?
    let onCard: (UUID) -> Void
    let onColumn: (UUID, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.taskBoardCard, .taskBoardColumn])
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { indicator = nil }

    func performDrop(info: DropInfo) -> Bool {
        let after = info.location.x > width / 2
        indicator = nil
        if let provider = info.itemProviders(for: [.taskBoardColumn]).first {
            _ = provider.loadTransferable(type: ColumnDragItem.self) { result in
                guard case .success(let item) = result, item.id != columnID else { return }
                DispatchQueue.main.async { onColumn(item.id, after) }
            }
            return true
        }
        if let provider = info.itemProviders(for: [.taskBoardCard]).first {
            _ = provider.loadTransferable(type: CardDragItem.self) { result in
                guard case .success(let item) = result else { return }
                DispatchQueue.main.async { onCard(item.id) }
            }
            return true
        }
        return false
    }

    private func update(_ info: DropInfo) {
        if info.hasItemsConforming(to: [.taskBoardColumn]) {
            indicator = info.location.x > width / 2 ? .after : .before
        } else {
            indicator = .card
        }
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
