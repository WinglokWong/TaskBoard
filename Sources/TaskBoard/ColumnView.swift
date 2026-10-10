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
    /// 正在拖动的卡片（在本列表中显示为占位）
    var draggingCardID: UUID? = nil
    /// 拖动中的卡片将放入本列表
    var isCardDropTarget = false
    /// 拖动中的卡片在本列表的预览位置（单独的占位视图）
    var placeholder: CardPlaceholder? = nil
    /// 键盘快捷键 N 请求在这一列添加卡片
    @Binding var addRequest: UUID?
    var onOpen: (Card) -> Void
    var onHoverCard: (UUID, Bool) -> Void = { _, _ in }
    /// 上报卡片在看板坐标空间中的位置，用于计算拖放位置
    var onCardFrame: (UUID, CGRect) -> Void = { _, _ in }
    var onPlaceholderFrame: (CGRect) -> Void = { _ in }

    @State private var isRenaming = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    @State private var addingCard = false
    @State private var newTitle = ""
    @FocusState private var newCardFocused: Bool

    @State private var showColor = false
    @State private var confirmDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerHovering = false
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private var foreground: Color { column.color?.foreground ?? .primary }

    /// 要显示的卡片：被拖动的卡片在原处收起，预览位置插入占位
    private var entries: [ColumnEntry] {
        var result = cards.map { ColumnEntry.card($0, collapsed: $0.id == draggingCardID) }
        if let placeholder {
            // 插在第 index 张（不计被拖动的卡片）可见卡片之前
            var seen = 0
            var insertAt = result.count
            for (i, entry) in result.enumerated() {
                guard case .card(_, false) = entry else { continue }
                if seen == placeholder.index { insertAt = i; break }
                seen += 1
            }
            result.insert(.placeholder(placeholder.card), at: insertAt)
        }
        return result
    }

    private var background: AnyShapeStyle {
        if let color = column.color { return AnyShapeStyle(color.color) }
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor).opacity(0.94))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .card(let card, let collapsed):
                            CardView(boardID: boardID, card: card,
                                     labels: boardLabels.filter { card.labelIDs.contains($0.id) },
                                     boardLabels: boardLabels, columns: columns,
                                     isSelected: card.id == selectedCardID,
                                     onOpen: { onOpen(card) },
                                     onHover: { onHoverCard(card.id, $0) })
                            .equatable()
                            .background(GeometryReader { g in
                                let frame = g.frame(in: .named(BoardSpace.name))
                                Color.clear
                                    .onAppear { if !collapsed { onCardFrame(card.id, frame) } }
                                    .onChange(of: frame) { _, newFrame in if !collapsed { onCardFrame(card.id, newFrame) } }
                            })
                            // 正在被拖动的卡片：留在原处但收起、不可见。
                            // 鼠标按下的就是这个视图，必须在整个拖动期间保留，否则拖动会中断（鼠标位置停止更新）。
                            // 负的底部边距抵消 VStack 的间距，收起后不留空隙。
                            .frame(height: collapsed ? 0 : nil, alignment: .top)
                            .clipped()
                            .opacity(collapsed ? 0 : 1)
                            .padding(.bottom, collapsed ? -8 : 0)
                            .allowsHitTesting(!collapsed)
                            .transition(Motion.cardTransition(reduceMotion))
                        case .placeholder(let card):
                            // 预览位置：与卡片外观相同的半透明占位
                            CardView(boardID: boardID, card: card,
                                     labels: boardLabels.filter { card.labelIDs.contains($0.id) },
                                     boardLabels: boardLabels, columns: columns,
                                     isDragPlaceholder: true,
                                     onOpen: {})
                            .equatable()
                            .allowsHitTesting(false)
                            .background(GeometryReader { g in
                                // 位置或预览序号变化时都重新上报（即使位置恰好相同）
                                let report = PlaceholderReport(frame: g.frame(in: .named(BoardSpace.name)),
                                                               index: placeholder?.index ?? -1)
                                Color.clear
                                    .onAppear { onPlaceholderFrame(report.frame) }
                                    .onChange(of: report) { _, newReport in onPlaceholderFrame(newReport.frame) }
                            })
                            .transition(Motion.cardTransition(reduceMotion))
                        }
                    }
                }
                // 卡片移动、增删、筛选时平滑过渡
                .animation(Motion.move(reduceMotion), value: entries.map(\.id))
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
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { viewportHeight = g.size.height }
                    .onChange(of: g.size.height) { _, height in viewportHeight = height }
            })
            // 卡片全部放得下时不需要裁剪，悬停和落位时卡片的阴影、放大效果可以完整显示
            .scrollClipDisabled(contentHeight <= viewportHeight + 1)
            footer
        }
        .padding(10)
        .frame(width: 272)
        .background(RoundedRectangle(cornerRadius: 12).fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: isCardDropTarget ? 2 : 0)
        )
        .shadow(color: .black.opacity(isCardDropTarget ? 0.2 : 0.12), radius: isCardDropTarget ? 6 : 2, y: 1)
        .animation(Motion.quick, value: isCardDropTarget)
        // 卡片和列表的拖放都由 BoardView 统一处理
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

struct CardPlaceholder: Equatable {
    let card: Card
    /// 在可见卡片（不含被拖动的卡片）中的位置
    let index: Int
}

enum ColumnEntry: Identifiable {
    case card(Card, collapsed: Bool)
    case placeholder(Card)

    var id: String {
        switch self {
        case .card(let card, _): return card.id.uuidString
        case .placeholder: return "drag-placeholder"
        }
    }
}

private struct PlaceholderReport: Equatable {
    let frame: CGRect
    let index: Int
}
