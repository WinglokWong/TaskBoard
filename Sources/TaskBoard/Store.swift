import SwiftUI
import AppKit

final class Store: ObservableObject {
    @Published var data: AppData {
        didSet { scheduleSave() }
    }

    private var saveWork: DispatchWorkItem?

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

    static var dataURL: URL { rootURL.appendingPathComponent("data.json") }

    init() {
        let fm = FileManager.default
        if let raw = try? Data(contentsOf: Self.dataURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(AppData.self, from: raw) {
                data = decoded
            } else {
                // 数据无法解析时保留一份备份，避免覆盖丢失
                let stamp = Int(Date().timeIntervalSince1970)
                let backup = Self.rootURL.appendingPathComponent("data.corrupt-\(stamp).json")
                try? fm.copyItem(at: Self.dataURL, to: backup)
                data = .sample
            }
        } else {
            data = .sample
        }
        if data.selectedBoardID == nil { data.selectedBoardID = data.boards.first?.id }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveNow()
        }
    }

    // MARK: - 持久化

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
        } catch {
            NSLog("TaskBoard save failed: \(error)")
        }
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

    // MARK: - 看板

    @discardableResult
    func addBoard() -> UUID {
        var board = Board.makeDefault(name: "新看板")
        board.background = Palette.presets.filter { $0.value.luminance < 0.6 }.randomElement()?.value ?? board.background
        data.boards.append(board)
        data.selectedBoardID = board.id
        return board.id
    }

    func renameBoard(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(id) { $0.name = name }
    }

    func setBackground(_ id: UUID, _ color: RGBAColor) {
        update(id) { $0.background = color }
    }

    func deleteBoard(_ id: UUID) {
        guard let board = board(id) else { return }
        board.cards.flatMap(\.attachments).forEach(removeFile)
        data.boards.removeAll { $0.id == id }
        if data.selectedBoardID == id { data.selectedBoardID = data.boards.first?.id }
    }

    // MARK: - 列表

    func addColumn(to boardID: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(boardID) { $0.columns.append(BoardColumn(name: name)) }
    }

    func renameColumn(_ columnID: UUID, in boardID: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update(boardID) { b in
            if let i = b.columns.firstIndex(where: { $0.id == columnID }) { b.columns[i].name = name }
        }
    }

    func setColumnColor(_ columnID: UUID, in boardID: UUID, _ color: RGBAColor?) {
        update(boardID) { b in
            if let i = b.columns.firstIndex(where: { $0.id == columnID }) { b.columns[i].color = color }
        }
    }

    func moveColumn(_ columnID: UUID, in boardID: UUID, by offset: Int) {
        update(boardID) { b in
            guard let i = b.columns.firstIndex(where: { $0.id == columnID }) else { return }
            let j = i + offset
            guard b.columns.indices.contains(j) else { return }
            b.columns.swapAt(i, j)
        }
    }

    /// 删除列表；其中未归档的卡片会被移入归档
    func deleteColumn(_ columnID: UUID, in boardID: UUID) {
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
        update(boardID) { $0.cards.append(Card(columnID: columnID, title: title)) }
    }

    func saveCard(_ card: Card, in boardID: UUID) {
        updateCard(card.id, in: boardID) { $0 = card }
    }

    func toggleDone(_ cardID: UUID, in boardID: UUID) {
        updateCard(cardID, in: boardID) { $0.isDone.toggle() }
    }

    func setCardColor(_ cardID: UUID, in boardID: UUID, _ color: RGBAColor?) {
        updateCard(cardID, in: boardID) { $0.color = color }
    }

    func archiveCard(_ cardID: UUID, in boardID: UUID) {
        updateCard(cardID, in: boardID) {
            $0.isArchived = true
            $0.archivedAt = Date()
        }
    }

    /// 从归档恢复；原列表若已删除，则放入第一个列表
    func restoreCard(_ cardID: UUID, in boardID: UUID) {
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
        card(cardID, in: boardID)?.attachments.forEach(removeFile)
        update(boardID) { $0.cards.removeAll { $0.id == cardID } }
    }

    func deleteArchivedCards(in boardID: UUID) {
        guard let board = board(boardID) else { return }
        board.cards.filter(\.isArchived).flatMap(\.attachments).forEach(removeFile)
        update(boardID) { $0.cards.removeAll(where: \.isArchived) }
    }

    /// 将卡片移动到指定列表，放在 `beforeCardID` 之前；为 nil 则放到末尾
    func moveCard(_ cardID: UUID, in boardID: UUID, to columnID: UUID, before beforeCardID: UUID?) {
        guard cardID != beforeCardID else { return }
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

    func removeFile(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: attachment.url)
    }
}
