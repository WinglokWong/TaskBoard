import SwiftUI

/// 卡片上的标签小胶囊；没有名称时显示为一小段色条
struct LabelPill: View {
    let label: CardLabel
    var expanded = false

    var body: some View {
        let name = label.name.trimmingCharacters(in: .whitespaces)
        Group {
            if name.isEmpty {
                Capsule()
                    .fill(label.color.color)
                    .frame(width: expanded ? nil : 36, height: expanded ? 20 : 8)
                    .frame(maxWidth: expanded ? .infinity : nil)
            } else {
                Text(name)
                    .font(expanded ? .callout.weight(.medium) : .caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, expanded ? 8 : 6)
                    .padding(.vertical, expanded ? 2 : 1)
                    .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
                    .background(Capsule().fill(label.color.color))
                    .foregroundStyle(label.color.foreground)
            }
        }
        .help(label.displayName)
    }
}

/// 一行显示多个标签，放不下时自动换行
struct LabelRow: View {
    let labels: [CardLabel]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(labels) { LabelPill(label: $0) }
        }
    }
}

/// 简单的自动换行布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (i, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !current.indices.isEmpty && current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(i)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// 选择 / 管理看板标签的弹出面板
struct LabelPickerView: View {
    @Environment(Store.self) private var store
    let boardID: UUID
    @Binding var selection: [UUID]

    @State private var editingID: UUID?
    @State private var confirmDeleteID: UUID?

    private var labels: [CardLabel] { store.board(boardID)?.labels ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签").font(.headline)

            if labels.isEmpty {
                Text("这个看板还没有标签").foregroundStyle(.secondary).font(.callout)
            }

            ForEach(labels) { label in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            toggle(label.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selection.contains(label.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selection.contains(label.id) ? Color.accentColor : .secondary)
                                LabelPill(label: label, expanded: true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            editingID = editingID == label.id ? nil : label.id
                        } label: {
                            Image(systemName: editingID == label.id ? "chevron.up" : "pencil")
                        }
                        .buttonStyle(.borderless)
                        .help("编辑标签")
                    }

                    if editingID == label.id {
                        editor(for: label)
                    }
                }
            }

            Divider()
            Button {
                let used = Set(labels.map { Palette.name(for: $0.color) ?? "" })
                let color = Palette.presets.first(where: { !used.contains($0.name) })?.value ?? Palette.presets[0].value
                editingID = store.addLabel(to: boardID, color: color)
            } label: {
                Label("新建标签", systemImage: "plus")
            }
        }
        .padding(14)
        .frame(width: 300)
        .confirmationDialog(
            "删除这个标签吗？",
            isPresented: Binding(get: { confirmDeleteID != nil }, set: { if !$0 { confirmDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let id = confirmDeleteID else { return }
                selection.removeAll { $0 == id }
                store.deleteLabel(id, in: boardID)
                editingID = nil
            }
        } message: {
            Text("标签会从这个看板的所有卡片上移除。")
        }
    }

    private func editor(for label: CardLabel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("标签名称（可留空）", text: Binding(
                get: { store.board(boardID)?.labels.first(where: { $0.id == label.id })?.name ?? "" },
                set: { store.renameLabel(label.id, in: boardID, to: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            ColorSwatchPicker(
                selection: Binding(
                    get: { label.color },
                    set: { if let c = $0 { store.setLabelColor(label.id, in: boardID, c) } }
                ),
                allowsNone: false
            )
            Button("删除标签", role: .destructive) { confirmDeleteID = label.id }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.removeAll { $0 == id }
        } else {
            selection.append(id)
        }
    }
}
