import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CardEditorView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let boardID: UUID

    @State private var draft: Card
    /// 打开编辑窗口时的卡片，用于关闭时合并为一个撤销步骤
    private let original: Card
    @State private var newChecklistItem = ""
    @FocusState private var checklistFieldFocused: Bool
    @State private var notificationsDenied = false
    @State private var confirmDelete = false
    @State private var importing = false
    @State private var dropTargeted = false

    init(boardID: UUID, card: Card) {
        self.boardID = boardID
        _draft = State(initialValue: card)
        original = card
    }

    private var columns: [BoardColumn] { store.board(boardID)?.columns ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部颜色条
            Rectangle()
                .fill(draft.color?.color ?? Color.secondary.opacity(0.15))
                .frame(height: 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleSection
                    statusSection
                    dueDateSection
                    section("描述", systemImage: "text.alignleft") {
                        TextEditor(text: $draft.details)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(minHeight: 140)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
                    }
                    checklistSection
                    section("卡片颜色", systemImage: "paintpalette") {
                        ColorSwatchPicker(selection: $draft.color)
                    }
                    attachmentsSection
                }
                .padding(20)
            }

            Divider()
            bottomBar
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 600, idealHeight: 720)
        .onChange(of: draft) { _, newValue in
            store.saveCard(newValue, in: boardID)
        }
        .onAppear(perform: refreshNotificationStatus)
        .onDisappear {
            store.registerCardEdit(original: original, in: boardID)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
        .confirmationDialog("确定删除这张卡片吗？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                let id = draft.id
                dismiss()
                store.deleteCard(id, in: boardID)
            }
        } message: {
            Text("卡片及其附件将被永久删除。")
        }
    }

    // MARK: - 各部分

    private var titleSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                draft.isDone.toggle()
            } label: {
                Image(systemName: draft.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(draft.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(draft.isDone ? "标记为未完成" : "标记为已完成")

            TextField("卡片标题", text: $draft.title, axis: .vertical)
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .strikethrough(draft.isDone)
        }
    }

    private var statusSection: some View {
        HStack(spacing: 16) {
            Picker("所在列表", selection: $draft.columnID) {
                ForEach(columns) { column in
                    Text(column.name).tag(Optional(column.id))
                }
            }
            .fixedSize()
            .disabled(draft.isArchived)

            Toggle("已完成", isOn: $draft.isDone)
                .toggleStyle(.checkbox)

            Spacer()

            if draft.isArchived {
                Label("已归档", systemImage: "archivebox.fill")
                    .foregroundStyle(.orange)
            }
            Text("创建于 \(draft.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dueDateSection: some View {
        section("截止日期", systemImage: "calendar") {
            if let due = draft.dueDate {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        DatePicker("", selection: Binding(get: { due }, set: { draft.dueDate = $0 }),
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .fixedSize()
                        Picker("提醒", selection: $draft.reminderMinutes) {
                            ForEach(ReminderOption.all) { option in
                                Text(option.title).tag(option.minutes)
                            }
                        }
                        .fixedSize()
                        .onChange(of: draft.reminderMinutes) { _, minutes in
                            if minutes != nil { NotificationManager.shared.requestAuthorization() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: refreshNotificationStatus)
                        }
                        DueBadge(date: due, isDone: draft.isDone, reminder: draft.reminderMinutes != nil)
                            .font(.caption)
                        Spacer()
                        Button("移除") {
                            draft.dueDate = nil
                            draft.reminderMinutes = nil
                        }
                    }
                    if notificationsDenied && draft.reminderMinutes != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "bell.slash")
                            Text("通知权限已关闭，到期时不会收到提醒。")
                            Button("打开系统设置") { NotificationManager.shared.openSystemSettings() }
                                .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            } else {
                Button {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    draft.dueDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                    draft.reminderMinutes = 0
                    NotificationManager.shared.requestAuthorization()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: refreshNotificationStatus)
                } label: {
                    Label("添加截止日期", systemImage: "plus")
                }
            }
        }
    }

    private var checklistSection: some View {
        section("清单", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 6) {
                if !draft.checklist.isEmpty {
                    let done = draft.checklistDoneCount, total = draft.checklist.count
                    HStack(spacing: 8) {
                        ProgressView(value: Double(done), total: Double(total))
                            .tint(done == total ? .green : .accentColor)
                        Text("\(done)/\(total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach($draft.checklist) { $item in
                        ChecklistRow(item: $item) {
                            draft.checklist.removeAll { $0.id == item.id }
                        }
                    }
                }
                HStack {
                    TextField("添加清单项，回车确认", text: $newChecklistItem)
                        .textFieldStyle(.roundedBorder)
                        .focused($checklistFieldFocused)
                        .onSubmit(addChecklistItem)
                    Button("添加", action: addChecklistItem)
                        .disabled(newChecklistItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addChecklistItem() {
        let text = newChecklistItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft.checklist.append(ChecklistItem(text: text))
        newChecklistItem = ""
        checklistFieldFocused = true
    }

    private func refreshNotificationStatus() {
        NotificationManager.shared.checkDenied { notificationsDenied = $0 }
    }

    private var attachmentsSection: some View {
        section("附件", systemImage: "paperclip") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        importing = true
                    } label: {
                        Label("添加文件…", systemImage: "plus")
                    }
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("粘贴图片", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    Text("也可以把文件拖到这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if draft.attachments.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(height: 70)
                        .overlay(Text("暂无附件").foregroundStyle(.secondary))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], alignment: .leading, spacing: 12) {
                        ForEach(draft.attachments) { attachment in
                            AttachmentTile(
                                attachment: attachment,
                                isCover: attachment.id == draft.coverImage?.id,
                                onMakeCover: { makeCover(attachment) },
                                onDelete: { removeAttachment(attachment) }
                            )
                        }
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(dropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                addFiles(files)
                return !files.isEmpty
            } isTargeted: { dropTargeted = $0 }
        }
    }

    private var bottomBar: some View {
        HStack {
            if draft.isArchived {
                Button {
                    let id = draft.id
                    dismiss()
                    store.restoreCard(id, in: boardID)
                } label: {
                    Label("从归档恢复", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    draft.isArchived = true
                    draft.archivedAt = Date()
                    dismiss()
                } label: {
                    Label("归档", systemImage: "archivebox")
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func section<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
    }

    // MARK: - 附件操作

    private func addFiles(_ urls: [URL]) {
        for url in urls {
            if let attachment = store.importAttachment(from: url) {
                draft.attachments.append(attachment)
            }
        }
    }

    private func pasteFromClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            addFiles(urls)
        } else if let image = NSImage(pasteboard: pb), let attachment = store.importImage(image) {
            draft.attachments.append(attachment)
        } else {
            NSSound.beep()
        }
    }

    private func removeAttachment(_ attachment: Attachment) {
        draft.attachments.removeAll { $0.id == attachment.id }
    }

    private func makeCover(_ attachment: Attachment) {
        guard let i = draft.attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
        let item = draft.attachments.remove(at: i)
        draft.attachments.insert(item, at: 0)
    }
}

struct ChecklistRow: View {
    @Binding var item: ChecklistItem
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $item.isDone)
                .toggleStyle(.checkbox)
                .labelsHidden()
            TextField("清单项", text: $item.text)
                .textFieldStyle(.plain)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("删除清单项")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.secondary.opacity(0.08) : .clear))
        .onHover { hovering = $0 }
    }
}

struct AttachmentTile: View {
    let attachment: Attachment
    var isCover: Bool
    var onMakeCover: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                if attachment.isImage, let image = ImageCache.shared.thumbnail(for: attachment) {
                    Color.clear
                        .overlay(Image(nsImage: image).resizable().scaledToFill())
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.url.path))
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                }
            }
            .frame(width: 116, height: 90)
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help("删除附件")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isCover {
                    Text("封面")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }

            Text(attachment.originalName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 116)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(attachment.url) }
        .help("点击打开：\(attachment.originalName)")
        .contextMenu {
            Button("打开") { NSWorkspace.shared.open(attachment.url) }
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([attachment.url]) }
            if attachment.isImage && !isCover {
                Button("设为封面", action: onMakeCover)
            }
            Divider()
            Button("删除附件", role: .destructive, action: onDelete)
        }
    }
}
