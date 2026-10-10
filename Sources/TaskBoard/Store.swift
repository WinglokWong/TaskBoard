import SwiftUI
import AppKit

/// 请求打开某张卡片（例如点击了提醒通知）
struct CardOpenRequest: Equatable {
    let boardID: UUID
    let cardID: UUID
}

struct BackupInfo: Identifiable, Hashable {
    let url: URL
    let date: Date
    let note: String?
    var id: URL { url }
}

final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { scheduleSave() }
    }

    /// 启动时需要告知用户的问题（例如数据文件无法读取）
    @Published var startupMessage: String?
    @Published var showBackups = false
    @Published var openRequest: CardOpenRequest?

    /// 由主窗口注入，用于撤销 / 重做
    weak var undoManager: UndoManager?

    private var saveWork: DispatchWorkItem?
    private var lastCheckpoint: (name: String, date: Date)?

    static let rootURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("TaskBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let attachmentsURL: URL = {
        let url = rootURL.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let backupsURL: URL = {
        let url = rootURL.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var dataURL: URL { rootURL.appendingPathComponent("data.json") }

    /// 最多保留的备份数量
    static let maxBackups = 30

    init() {
        if let raw = try? Data(contentsOf: Self.dataURL) {
            do {
                data = try Self.decode(raw)
                Self.backupIfNeeded()
            } catch {
                // 数据无法解析时保留一份副本，避免被新数据覆盖
                let copy = Self.backupsURL.appendingPathComponent("data-\(Self.stamp(Date()))-unreadable.json")
                try? FileManager.default.copyItem(at: Self.dataURL, to: copy)
                data = .sample
                startupMessage = "数据文件无法读取，已创建新的示例看板。原文件已保存为备份「\(copy.lastPathComponent)」，可以在“文件 → 从备份恢复”中查看。"
            }
        } else {
            data = .sample
        }
        data.schemaVersion = AppData.currentSchemaVersion
        if data.selectedBoardID == nil { data.selectedBoardID = data.boards.first?.id }

        cleanUpOrphanedAttachments()
        NotificationManager.shared.reschedule(for: data)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveNow()
        }
    }

    // MARK: - 持久化

    private static func decode(_ raw: Data) throws -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppData.self, from: raw)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let raw = try encoder.encode(data)
            try raw.write(to: Self.dataURL, options: .atomic)
            Self.backupIfNeeded()
        } catch {
            NSLog("TaskBoard save failed: \(error)")
        }
        NotificationManager.shared.reschedule(for: data)
    }

    // MARK: - 备份

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// 每天第一次保存（或启动）时自动备份一次
    private static func backupIfNeeded() {
        let today = "data-" + String(stamp(Date()).prefix(8))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupsURL.path)) ?? []
        if !names.contains(where: { $0.hasPrefix(today) }) {
            makeBackup(note: nil)
        }
    }

    @discardableResult
    private static func makeBackup(note: String?) -> URL? {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return nil }
        let name = "data-\(stamp(Date()))" + (note.map { "-\($0)" } ?? "") + ".json"
        let url = backupsURL.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: dataURL, to: url)
        } catch {
            NSLog("TaskBoard backup failed: \(error)")
            return nil
        }
        pruneBackups()
        return url
    }

    private static func pruneBackups() {
        let all = listBackups()
        for old in all.dropFirst(maxBackups) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    /// 所有备份，最新的在前
    static func listBackups() -> [BackupInfo] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let urls = (try? FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("data-") }
            .compactMap { url -> BackupInfo? in
                let base = url.deletingPathExtension().lastPathComponent.dropFirst(5) // 去掉 "data-"
                guard base.count >= 15, let date = f.date(from: String(base.prefix(15))) else { return nil }
                let rest = base.dropFirst(15)
                let note = rest.hasPrefix("-") ? String(rest.dropFirst()) : nil
                return BackupInfo(url: url, date: date, note: note)
            }
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    static func readBackup(_ backup: BackupInfo) -> AppData? {
        guard let raw = try? Data(contentsOf: backup.url) else { return nil }
        return try? decode(raw)
    }

    func backupNow() {
        saveNow()
        Self.makeBackup(note: "manual")
    }

    func restore(from backup: BackupInfo) -> Bool {
        guard var restored = Self.readBackup(backup) else { return false }
        saveNow()
        Self.makeBackup(note: "before-restore")
        checkpoint("从备份恢复")
        if !restored.boards.contains(where: { $0.id == restored.selectedBoardID }) {
            restored.selectedBoardID = restored.boards.first?.id
        }
        restored.schemaVersion = AppData.currentSchemaVersion
        data = restored
        return true
    }

    /// 删除不再被当前数据或任何备份引用的附件文件。
    /// 删除卡片 / 附件时不会立即删除文件，这样撤销和从备份恢复都能找回附件。
    private func cleanUpOrphanedAttachments() {
        let current = data.attachmentFileNames
        let launchDate = Date()
        DispatchQueue.global(qos: .utility).async {
            var referenced = current
            for backup in Self.listBackups() {
                if let old = Self.readBackup(backup) { referenced.formUnion(old.attachmentFileNames) }
            }
            let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.attachmentsURL.path)) ?? []
            for file in files where !referenced.contains(file) && !file.hasPrefix(".") {
                let url = Self.attachmentsURL.appendingPathComponent(file)
                // 跳过本次启动后新加入的文件
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
                guard created < launchDate else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - 撤销

    /// 在修改数据前调用，记录当前状态以便撤销。
    /// `coalesce` 为 true 时，短时间内相同名称的连续操作（如拖动取色器）只记录一次。
    private func checkpoint(_ name: String, coalesce: Bool = false) {
        guard let um = undoManager, !um.isUndoing, !um.isRedoing else { return }
        let now = Date()
        if coalesce, let last = lastCheckpoint, last.name == name, now.timeIntervalSince(last.date) < 1.5 {
            lastCheckpoint = (name, now)
            return
        }
        registerUndo(restoring: data, name: name, on: um)
        lastCheckpoint = (name, now)
    }

    private func registerUndo(restoring snapshot: AppData, name: String, on um: UndoManager) {
        um.registerUndo(withTarget: self) { store in
            // 撤销时登记的操作会自动进入重做栈
            store.registerUndo(restoring: store.data, name: name, on: um)
            store.data = snapshot
            store.lastCheckpoint = nil
        }
        um.setActionName(name)
    }

    /// 卡片编辑窗口关闭时调用：把整次编辑合并为一个撤销步骤
    func registerCardEdit(original: Card, in boardID: UUID) {
        guard let um = undoManager, let current = card(original.id, in: boardID), current != original else { return }
        var before = data
        if let bi = before.boards.firstIndex(where: { $0.id == boardID }),
           let ci = before.boards[bi].cards.firstIndex(where: { $0.id == original.id }) {
            before.boards[bi].cards[ci] = original
        }
        registerUndo(restoring: before, name: "编辑卡片", on: um)
        lastCheckpoint = nil
    }

    // MARK: - 查询

    func board(_ id: UUID?) -> Board? {
        data.boards.first(where: { $0.id == id })
    }

    func card(_ id: UUID, in boardID: UUID) -> Card? {
        board(boardID)?.cards.first(where: { $0.id == id })
    }

    private func update(_ boardID: UUID, _ body: (inout Board) -> Void) {
        guard let i = data.boards.firstIndex(where: { $0.id == boardID }) else { return }
        body(&data.boards[i])
    }

    private func updateCard(_ cardID: UUID, in boardID: UUID, _ body: (inout Card) -> Void) {
        update(boardID) { b in
            guard let i = b.cards.firstIndex(where: { $0.id == cardID }) else { return }
            body(&b.cards[i])
        }
    }

    func requestOpen(cardID: UUID, in boardID: UUID) {
        guard card(cardID, in: boardID) != nil else { return }
        data.selectedBoardID = boardID
        openRequest = CardOpenRequest(boardID: boardID, cardID: cardID)
    }

    // MARK: - 看板

    @discardableResult
    func addBoard() -> UUID {
        checkpoint("新建看板")
        var board = Board.makeDefault(name: "新看板")
        board.background = Palette.presets.filter { $0.value.luminance < 0.6 }.randomElement()?.value ?? board.background
        data.boards.append(board)
        data.selectedBoardID = board.id
        return board.id
    }

    func renameBoard(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, board(id)?.name != name else { return }
        checkpoint("重命名看板")
        update(id) { $0.name = name }
    }

    func setBackground(_ id: UUID, _ color: RGBAColor) {
        checkpoint("修改背景颜色", coalesce: true)
        update(id) { $0.background = color }
    }

    func deleteBoard(_ id: UUID) {
        checkpoint("删除看板")
        data.boards.removeAll { $0.id == id }
        if data.selectedBoardID == id { data.selectedBoardID = data.boards.first?.id }
    }

    // MARK: - 列表

    func addColumn(to boardID: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        checkpoint("添加列表")
        update(boardID) { $0.columns.append(BoardColumn(name: name)) }
    }

    func renameColumn(_ columnID: UUID, in boardID: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, board(boardID)?.columnName(columnID) != name else { return }
        checkpoint("重命名列表")
        update(boardID) { b in
            if let i = b.columns.firstIndex(where: { $0.id == columnID }) { b.columns[i].name = name }
        }
    }

    func setColumnColor(_ columnID: UUID, in boardID: UUID, _ color: RGBAColor?) {
        checkpoint("修改列表颜色", coalesce: true)
        update(boardID) { b in
            if let i = b.columns.firstIndex(where: { $0.id == columnID }) { b.columns[i].color = color }
        }
    }

    func moveColumn(_ columnID: UUID, in boardID: UUID, by offset: Int) {
        checkpoint("移动列表")
        update(boardID) { b in
            guard let i = b.columns.firstIndex(where: { $0.id == columnID }) else { return }
            let j = i + offset
            guard b.columns.indices.contains(j) else { return }
            b.columns.swapAt(i, j)
        }
    }

    /// 删除列表；其中未归档的卡片会被移入归档
    func deleteColumn(_ columnID: UUID, in boardID: UUID) {
        checkpoint("删除列表")
        update(boardID) { b in
            let now = Date()
            for i in b.cards.indices where b.cards[i].columnID == columnID && !b.cards[i].isArchived {
                b.cards[i].isArchived = true
                b.cards[i].archivedAt = now
            }
            b.columns.removeAll { $0.id == columnID }
        }
    }

    func archiveCards(in columnID: UUID, of boardID: UUID, onlyDone: Bool) {
        checkpoint(onlyDone ? "归档已完成的卡片" : "归档全部卡片")
        update(boardID) { b in
            let now = Date()
            for i in b.cards.indices
            where b.cards[i].columnID == columnID && !b.cards[i].isArchived && (!onlyDone || b.cards[i].isDone) {
                b.cards[i].isArchived = true
                b.cards[i].archivedAt = now
            }
        }
    }

    // MARK: - 卡片

    func addCard(to columnID: UUID, in boardID: UUID, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        checkpoint("添加卡片")
        update(boardID) { $0.cards.append(Card(columnID: columnID, title: title)) }
    }

    /// 卡片编辑窗口中的实时保存（不单独记录撤销，见 registerCardEdit）
    func saveCard(_ card: Card, in boardID: UUID) {
        updateCard(card.id, in: boardID) { $0 = card }
    }

    func toggleDone(_ cardID: UUID, in boardID: UUID) {
        let done = card(cardID, in: boardID)?.isDone ?? false
        checkpoint(done ? "标记为未完成" : "标记为已完成")
        updateCard(cardID, in: boardID) { $0.isDone.toggle() }
    }

    func setCardColor(_ cardID: UUID, in boardID: UUID, _ color: RGBAColor?) {
        checkpoint("修改卡片颜色")
        updateCard(cardID, in: boardID) { $0.color = color }
    }

    func archiveCard(_ cardID: UUID, in boardID: UUID) {
        checkpoint("归档卡片")
        updateCard(cardID, in: boardID) {
            $0.isArchived = true
            $0.archivedAt = Date()
        }
    }

    /// 从归档恢复；原列表若已删除，则放入第一个列表
    func restoreCard(_ cardID: UUID, in boardID: UUID) {
        checkpoint("恢复卡片")
        update(boardID) { b in
            guard let i = b.cards.firstIndex(where: { $0.id == cardID }) else { return }
            var card = b.cards.remove(at: i)
            if !b.columns.contains(where: { $0.id == card.columnID }) {
                if b.columns.isEmpty { b.columns.append(BoardColumn(name: "待办")) }
                card.columnID = b.columns[0].id
            }
            card.isArchived = false
            card.archivedAt = nil
            b.cards.append(card)
        }
    }

    func deleteCard(_ cardID: UUID, in boardID: UUID) {
        checkpoint("删除卡片")
        update(boardID) { $0.cards.removeAll { $0.id == cardID } }
    }

    func deleteArchivedCards(in boardID: UUID) {
        checkpoint("清空归档")
        update(boardID) { $0.cards.removeAll(where: \.isArchived) }
    }

    /// 将卡片移动到指定列表，放在 `beforeCardID` 之前；为 nil 则放到末尾
    func moveCard(_ cardID: UUID, in boardID: UUID, to columnID: UUID, before beforeCardID: UUID?) {
        guard cardID != beforeCardID else { return }
        checkpoint("移动卡片")
        update(boardID) { b in
            guard let from = b.cards.firstIndex(where: { $0.id == cardID }) else { return }
            var card = b.cards.remove(at: from)
            card.columnID = columnID
            if let beforeCardID, let target = b.cards.firstIndex(where: { $0.id == beforeCardID }) {
                b.cards.insert(card, at: target)
            } else {
                b.cards.append(card)
            }
        }
    }

    // MARK: - 附件

    func importAttachment(from url: URL) -> Attachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension
        let stored = UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)")
        do {
            try FileManager.default.copyItem(at: url, to: Self.attachmentsURL.appendingPathComponent(stored))
            return Attachment(fileName: stored, originalName: url.lastPathComponent)
        } catch {
            NSLog("TaskBoard import failed: \(error)")
            return nil
        }
    }

    func importImage(_ image: NSImage) -> Attachment? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let stored = UUID().uuidString + ".png"
        do {
            try png.write(to: Self.attachmentsURL.appendingPathComponent(stored))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return Attachment(fileName: stored, originalName: "粘贴的图片 \(formatter.string(from: Date())).png")
        } catch {
            return nil
        }
    }
}
