import SwiftUI
import QuickLook

struct CardRef: Identifiable {
    let id: UUID
}

struct BoardView: View {
    @Environment(Store.self) private var store
    let boardID: UUID

    @State private var editingCard: CardRef?
    @State private var showArchive = false
    @State private var showBackground = false
    @State private var search = ""
    @State private var filter = BoardFilter()

    @State private var selectedCardID: UUID?
    @State private var scrollTarget: UUID?
    @State private var addRequest: UUID?
    @State private var previewURL: URL?
    @State private var previewURLs: [URL] = []
    @State private var keyMonitor = KeyMonitor()
    @State private var columnReorder = ColumnReorder()
    @State private var cardReorder = CardReorder()
    @State private var drag = BoardDrag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let board = store.board(boardID) {
            content(board)
        }
    }

    private func content(_ board: Board) -> some View {
        let archivedCount = board.cards.filter(\.isArchived).count
        return ZStack {
            board.background.color.ignoresSafeArea()
            VStack(spacing: 0) {
                if filter.isActive || !trimmedSearch.isEmpty {
                    filterBar(board)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            let columns = displayedColumns(board)
                            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                                let cards = visibleCards(board, in: column.id)
                                let isDragged = columnReorder.draggingID == column.id
                                ColumnView(
                                    boardID: boardID,
                                    column: column,
                                    cards: cards,
                                    isFirst: index == 0,
                                    isLast: index == columns.count - 1,
                                    boardLabels: board.labels,
                                    columns: board.columns,
                                    selectedCardID: drag.isActive ? nil : selectedCardID,
                                    draggingCardID: cardReorder.draggingID,
                                    isCardDropTarget: cardReorder.target?.columnID == column.id,
                                    placeholder: cardPlaceholder(board, in: column.id),
                                    addRequest: $addRequest,
                                    // 拖动或落位过程中的松开不算点击
                                    onOpen: { card in if !drag.isActive { editingCard = CardRef(id: card.id) } },
                                    onHoverCard: { id, inside in if inside && !drag.isActive { selectedCardID = id } },
                                    onCardFrame: { id, frame in cardReorder.frames[id] = frame },
                                    onPlaceholderFrame: { cardReorder.placeholderFrames[column.id] = $0 }
                                )
                                .transition(Motion.cardTransition(reduceMotion))
                                // 被拖动的列表留在预览位置，显示为半透明占位
                                .opacity(isDragged ? 0.35 : 1)
                                .overlay {
                                    if isDragged {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                                    }
                                }
                                .background(GeometryReader { g in
                                    let frame = g.frame(in: .named(BoardSpace.name))
                                    Color.clear
                                        .onAppear { columnReorder.frames[column.id] = frame }
                                        .onChange(of: frame) { _, newFrame in columnReorder.frames[column.id] = newFrame }
                                })
                            }
                            AddColumnView(boardID: boardID, background: board.background)
                        }
                        // 列表重新排序、增删时平滑过渡
                        .animation(Motion.move(reduceMotion), value: board.columns.map(\.id))
                        .padding(16)
                        .frame(maxHeight: .infinity, alignment: .top)
                        // 看板级拖动手势：挂在不会移动的视图上，卡片换到其他列表时拖动也不会中断。
                        // 开始时根据卡片 / 列表的位置判断拖的是什么（卡片优先于所在列表）。
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .named(BoardSpace.name))
                                .onChanged(boardDragChanged)
                                .onEnded(boardDragEnded)
                        )
                        .coordinateSpace(name: BoardSpace.name)
                        // 拖动中的浮动副本（与原物外观相同），画在所有列表之上
                        .overlay(alignment: .topLeading) {
                            BoardDragOverlay(
                                drag: drag,
                                board: board,
                                cardsInColumn: { visibleCards(board, in: $0) },
                                reduceMotion: reduceMotion
                            )
                        }
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target) }
                        scrollTarget = nil
                    }
                }
            }
        }
        .animation(Motion.quick, value: filter.isActive || !trimmedSearch.isEmpty)
        .navigationTitle(board.name)
        .searchable(text: $search, placement: .toolbar, prompt: "搜索卡片")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu(board)
                settingsMenu(board)

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
        .quickLookPreview($previewURL, in: previewURLs)
        .onAppear {
            handleOpenRequest()
            keyMonitor.start(handleKey)
        }
        .onDisappear { keyMonitor.stop() }
        .onChange(of: store.openRequest) { _, _ in handleOpenRequest() }
        .sheet(item: $editingCard) { ref in
            if let card = store.card(ref.id, in: boardID) {
                CardEditorView(boardID: boardID, card: card)
                    .environment(store)
            }
        }
        .sheet(isPresented: $showArchive) {
            ArchiveView(boardID: boardID, onOpen: { card in
                showArchive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editingCard = CardRef(id: card.id) }
            })
            .environment(store)
        }
    }

    // MARK: - 筛选

    private var trimmedSearch: String { search.trimmingCharacters(in: .whitespaces) }

    private func filterMenu(_ board: Board) -> some View {
        Menu {
            if !board.labels.isEmpty {
                Section("标签（满足任意一个）") {
                    ForEach(board.labels) { label in
                        Toggle(label.displayName, isOn: Binding(
                            get: { filter.labelIDs.contains(label.id) },
                            set: { on in
                                if on { filter.labelIDs.insert(label.id) } else { filter.labelIDs.remove(label.id) }
                            }
                        ))
                    }
                }
            }
            Picker("状态", selection: $filter.status) {
                ForEach(BoardFilter.Status.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker("截止日期", selection: $filter.due) {
                ForEach(BoardFilter.Due.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("清除筛选") { filter = BoardFilter() }
                .disabled(!filter.isActive)
        } label: {
            Label(filter.isActive ? "筛选 (\(filter.activeCount))" : "筛选",
                  systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
        }
        .help("按标签、状态或截止日期筛选卡片")
    }

    private func settingsMenu(_ board: Board) -> some View {
        Menu {
            Picker("自动归档已完成的卡片", selection: Binding(
                get: { store.board(boardID)?.autoArchiveDays },
                set: { store.setAutoArchive(boardID, days: $0) }
            )) {
                ForEach(AutoArchiveOption.all) { Text($0.title).tag($0.days) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("导出看板…") { store.exportBoard(boardID) }
        } label: {
            Label("看板设置", systemImage: board.autoArchiveDays == nil ? "gearshape" : "gearshape.fill")
        }
        .help(board.autoArchiveDays.map { "已开启自动归档：完成 \($0) 天后" } ?? "看板设置")
    }

    private func filterBar(_ board: Board) -> some View {
        let all = board.cards.filter { !$0.isArchived }
        let shown = board.columns.reduce(0) { $0 + visibleCards(board, in: $1.id).count }
        let selectedLabels = board.labels.filter { filter.labelIDs.contains($0.id) }
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
            Text("显示 \(shown) / \(all.count) 张卡片")
                .fontWeight(.medium)
            ForEach(selectedLabels) { LabelPill(label: $0) }
            if filter.status != .all { chip(filter.status.title) }
            if filter.due != .any { chip(filter.due.title) }
            if !trimmedSearch.isEmpty { chip(String(localized: "搜索：\(trimmedSearch)")) }
            Spacer()
            Button("清除") {
                filter = BoardFilter()
                search = ""
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    // MARK: - 拖动（卡片和列表）

    private func boardDragChanged(_ value: DragGesture.Value) {
        guard let board = store.board(boardID) else { return }
        if !drag.isActive {
            // 正在输入文字时（例如在文本框中拖选）不开始拖动
            guard !(NSApp.keyWindow?.firstResponder is NSText),
                  let (item, frame) = dragItem(at: value.startLocation, in: board) else { return }
            // 开始时原物换成占位（位置不变），这一步不需要动画
            var transaction = Transaction()
            transaction.disablesAnimations = true
            var started = true
            withTransaction(transaction) {
                switch item {
                case .card(let id):
                    guard let card = board.cards.first(where: { $0.id == id }), let columnID = card.columnID else {
                        started = false
                        return
                    }
                    let index = visibleCards(board, in: columnID).firstIndex(where: { $0.id == id }) ?? 0
                    cardReorder.animation = Motion.move(reduceMotion)
                    cardReorder.begin(id, at: CardDropTarget(columnID: columnID, index: index))
                case .column(let id):
                    columnReorder.animation = Motion.move(reduceMotion)
                    columnReorder.begin(id, order: board.columns.map(\.id))
                }
            }
            guard started else { return }
            drag.begin(item, frame: frame, pointer: value.startLocation, liftAnimation: Motion.quick)
        }
        guard let item = drag.item, !drag.isLanding, !drag.cancelled else { return }
        drag.move(to: value.location)
        switch item {
        case .card:
            let target = cardReorder.target(
                at: value.location,
                columnIDs: displayedColumns(board).map(\.id),
                cardIDs: { visibleCards(board, in: $0).map(\.id) }
            )
            if let target { cardReorder.hover(target) }
        case .column:
            columnReorder.hover(slot: BoardSpace.slot(atX: value.location.x))
        }
    }

    private func boardDragEnded(_ value: DragGesture.Value) {
        guard let item = drag.item, !drag.isLanding else { return }
        if drag.cancelled || isOutsideBoard(value.location) {
            cancelDrag()
            return
        }
        // 等最后一次预览位置的布局完成，再让副本滑入占位的位置
        DispatchQueue.main.async {
            switch item {
            case .card:
                landCard()
            case .column(let id):
                let slot = columnReorder.frames[id] ?? drag.originFrame
                drag.land(at: slot, animation: Motion.settle(reduceMotion)) {
                    columnReorder.commit { store.reorderColumns($0, in: boardID) }
                }
            }
        }
    }

    /// 让卡片副本滑入目标列表中占位的位置。
    /// 如果目标列表的占位还没完成布局（松手太快），最多再等几帧；仍然没有就原地落下，绝不飞回原来的位置。
    private func landCard(attempt: Int = 0) {
        guard drag.isActive, !drag.isLanding else { return }
        if let slot = cardReorder.placeholderFrame {
            drag.land(at: slot, animation: Motion.settle(reduceMotion)) {
                cardReorder.commit(commitCardDrop)
            }
        } else if attempt < 3 {
            DispatchQueue.main.async { landCard(attempt: attempt + 1) }
        } else {
            drag.land(at: drag.frame, animation: Motion.settle(reduceMotion)) {
                cardReorder.commit(commitCardDrop)
            }
        }
    }

    /// 鼠标下的卡片或列表（卡片优先）及其位置
    private func dragItem(at point: CGPoint, in board: Board) -> (BoardDrag.Item, CGRect)? {
        let columns = displayedColumns(board)
        for column in columns {
            for card in visibleCards(board, in: column.id) {
                if let frame = cardReorder.frames[card.id], frame.contains(point) { return (.card(card.id), frame) }
            }
        }
        for column in columns {
            if let frame = columnReorder.frames[column.id], frame.contains(point) { return (.column(column.id), frame) }
        }
        return nil
    }

    /// 取消拖动（Esc 或拖到看板外松开）：占位回到原处，副本滑回原来的位置
    private func cancelDrag() {
        guard let item = drag.item, !drag.isLanding else { return }
        drag.markCancelled()
        switch item {
        case .card:
            cardReorder.revert()
            drag.land(at: drag.originFrame, animation: Motion.settle(reduceMotion)) { cardReorder.finish() }
        case .column:
            columnReorder.revert()
            drag.land(at: drag.originFrame, animation: Motion.settle(reduceMotion)) { columnReorder.finish() }
        }
    }

    /// 拖到侧边栏或工具栏上松开视为取消
    private func isOutsideBoard(_ point: CGPoint) -> Bool {
        point.x < -8 || point.y < -8
    }

    private func commitCardDrop(_ cardID: UUID, _ target: CardDropTarget) {
        guard let board = store.board(boardID) else { return }
        let others = visibleCards(board, in: target.columnID).filter { $0.id != cardID }
        let before = target.index < others.count ? others[target.index].id : nil
        store.moveCard(cardID, in: boardID, to: target.columnID, before: before)
    }

    /// 拖动卡片时，目标列表中的预览占位
    private func cardPlaceholder(_ board: Board, in columnID: UUID) -> CardPlaceholder? {
        guard let id = cardReorder.draggingID, let target = cardReorder.target, target.columnID == columnID,
              let card = board.cards.first(where: { $0.id == id }) else { return nil }
        return CardPlaceholder(card: card, index: target.index)
    }

    /// 拖动列表时按预览顺序显示
    private func displayedColumns(_ board: Board) -> [BoardColumn] {
        guard let order = columnReorder.previewOrder else { return board.columns }
        let byID = Dictionary(uniqueKeysWithValues: board.columns.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        // 拖动期间若有列表增删，退回实际顺序
        return ordered.count == board.columns.count ? ordered : board.columns
    }

    private func visibleCards(_ board: Board, in columnID: UUID) -> [Card] {
        let query = trimmedSearch
        let now = Date()
        return board.cards.filter { card in
            guard card.columnID == columnID, !card.isArchived else { return false }
            if !query.isEmpty && !card.matches(query) { return false }
            return filter.matches(card, now: now)
        }
    }

    // MARK: - 键盘

    private func handleKey(_ key: BoardKey) -> Bool {
        if drag.isActive {
            if key == .escape { cancelDrag() }
            return true
        }
        guard editingCard == nil, !showArchive, previewURL == nil, let board = store.board(boardID) else { return false }
        let grid = board.columns.map { visibleCards(board, in: $0.id) }
        let position: (col: Int, row: Int)? = selectedCardID.flatMap { id in
            for (c, cards) in grid.enumerated() {
                if let r = cards.firstIndex(where: { $0.id == id }) { return (c, r) }
            }
            return nil
        }
        let selected = position.map { grid[$0.col][$0.row] }

        func select(_ card: Card?) {
            guard let card else { return }
            selectedCardID = card.id
            scrollTarget = card.id
        }

        switch key {
        case .up, .down, .left, .right:
            guard let position else {
                select(grid.first(where: { !$0.isEmpty })?.first)
                return true
            }
            switch key {
            case .up:
                if position.row > 0 { select(grid[position.col][position.row - 1]) }
            case .down:
                if position.row + 1 < grid[position.col].count { select(grid[position.col][position.row + 1]) }
            default:
                let step = key == .left ? -1 : 1
                var c = position.col + step
                while grid.indices.contains(c) {
                    if !grid[c].isEmpty {
                        select(grid[c][min(position.row, grid[c].count - 1)])
                        break
                    }
                    c += step
                }
            }
            return true

        case .open:
            guard let selected else { return false }
            editingCard = CardRef(id: selected.id)
            return true

        case .quickLook:
            guard let selected, !selected.attachments.isEmpty else { return selected != nil }
            previewURLs = selected.attachments.map(\.url)
            previewURL = previewURLs.first
            return true

        case .toggleDone:
            guard let selected else { return false }
            withAnimation(.snappy) { store.toggleDone(selected.id, in: boardID) }
            return true

        case .archive:
            guard let selected, let position else { return false }
            let column = grid[position.col]
            let next = column.indices.contains(position.row + 1) ? column[position.row + 1]
                : (position.row > 0 ? column[position.row - 1] : nil)
            store.archiveCard(selected.id, in: boardID)
            selectedCardID = next?.id
            return true

        case .newCard:
            let columnID = position.map { board.columns[$0.col].id } ?? board.columns.first?.id
            guard let columnID else { return false }
            addRequest = columnID
            return true

        case .escape:
            guard selectedCardID != nil else { return false }
            selectedCardID = nil
            return true
        }
    }

    private func handleOpenRequest() {
        guard let request = store.openRequest, request.boardID == boardID else { return }
        store.openRequest = nil
        showArchive = false
        editingCard = CardRef(id: request.cardID)
    }
}

struct AddColumnView: View {
    @Environment(Store.self) private var store
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
