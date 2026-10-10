import Foundation
import AppKit
import UniformTypeIdentifiers

// 导入 / 导出
//
// .taskboard 文件是一个 zip，内容为：
//   manifest.json   格式信息（kind = board 单个看板 / library 全部数据）
//   data.json       Board 或 AppData
//   attachments/    被引用的附件文件
//
// 导入的文件来自外部，一律视为不可信：解压前检查条目路径，只读取已知文件，附件名必须是单纯的文件名。

extension UTType {
    static let taskBoardArchive = UTType(exportedAs: "local.taskboard.archive")
}

struct ArchiveManifest: Codable {
    static let formatName = "taskboard"
    static let currentVersion = 1

    enum Kind: String, Codable { case board, library }

    var format = ArchiveManifest.formatName
    var formatVersion = ArchiveManifest.currentVersion
    var kind: Kind
    var appVersion: String
    var exportedAt: Date
}

enum ArchiveError: LocalizedError {
    case notAnArchive
    case unsafeContents
    case unsupportedVersion(Int)
    case damaged
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .notAnArchive: return String(localized: "这不是任务看板的导出文件。")
        case .unsafeContents: return String(localized: "文件中包含不安全的路径，已拒绝导入。")
        case .unsupportedVersion(let v): return String(localized: "这个文件来自更新版本的任务看板（格式版本 \(v)），请先更新应用。")
        case .damaged: return String(localized: "文件已损坏或内容不完整。")
        case .writeFailed: return String(localized: "无法写入导出文件。")
        }
    }
}

/// 解压到临时目录后的导入文件。用完后调用 `discard()` 删除临时文件。
struct ImportedArchive: Identifiable {
    let id = UUID()
    let manifest: ArchiveManifest
    let boards: [Board]
    /// 仅全部数据导出时有值
    let library: AppData?
    let folder: URL

    var isLibrary: Bool { manifest.kind == .library }
    var cardCount: Int { boards.reduce(0) { $0 + $1.cards.count } }

    /// 安全地取得归档中附件文件的位置；文件名不合法或文件不存在时返回 nil
    func attachmentFile(_ fileName: String) -> URL? {
        guard ArchiveIO.isSafeFileName(fileName) else { return nil }
        let url = folder.appendingPathComponent("attachments", isDirectory: true).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func discard() {
        try? FileManager.default.removeItem(at: folder)
    }
}

enum ArchiveIO {
    // MARK: 导出

    static func export(board: Board, to url: URL) throws {
        try write(kind: .board, payload: board, attachments: board.cards.flatMap(\.attachments), to: url)
    }

    static func export(library: AppData, to url: URL) throws {
        let attachments = library.boards.flatMap { $0.cards.flatMap(\.attachments) }
        try write(kind: .library, payload: library, attachments: attachments, to: url)
    }

    private static func write<T: Encodable>(kind: ArchiveManifest.Kind, payload: T, attachments: [Attachment], to url: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("taskboard-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            let attachmentsDir = staging.appendingPathComponent("attachments", isDirectory: true)
            try fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
            let manifest = ArchiveManifest(kind: kind, appVersion: version, exportedAt: Date())
            try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"))
            try encoder.encode(payload).write(to: staging.appendingPathComponent("data.json"))

            for attachment in attachments where fm.fileExists(atPath: attachment.url.path) {
                let target = attachmentsDir.appendingPathComponent(attachment.fileName)
                if !fm.fileExists(atPath: target.path) {
                    try fm.copyItem(at: attachment.url, to: target)
                }
            }

            try? fm.removeItem(at: url)
            try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", staging.path, url.path])
        } catch {
            throw ArchiveError.writeFailed
        }
    }

    // MARK: 导入

    static func read(_ url: URL) throws -> ImportedArchive {
        let fm = FileManager.default

        // 1. 解压前检查条目：不允许绝对路径或 ".."
        let listing: String
        do {
            listing = try run("/usr/bin/zipinfo", ["-1", url.path])
        } catch {
            throw ArchiveError.notAnArchive
        }
        let entries = listing.split(separator: "\n").map(String.init)
        guard entries.contains("manifest.json"), entries.contains("data.json") else { throw ArchiveError.notAnArchive }
        for entry in entries {
            let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
            if entry.hasPrefix("/") || parts.contains("..") || entry.contains("\\") {
                throw ArchiveError.unsafeContents
            }
        }

        // 2. 解压到临时目录
        let folder = fm.temporaryDirectory.appendingPathComponent("taskboard-import-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try run("/usr/bin/ditto", ["-x", "-k", "--norsrc", url.path, folder.path])
        } catch {
            try? fm.removeItem(at: folder)
            throw ArchiveError.damaged
        }

        // 3. 读取清单和数据
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(ArchiveManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
            guard manifest.format == ArchiveManifest.formatName else { throw ArchiveError.notAnArchive }
            guard manifest.formatVersion <= ArchiveManifest.currentVersion else {
                throw ArchiveError.unsupportedVersion(manifest.formatVersion)
            }
            let raw = try Data(contentsOf: folder.appendingPathComponent("data.json"))
            switch manifest.kind {
            case .board:
                let board = try decoder.decode(Board.self, from: raw)
                return ImportedArchive(manifest: manifest, boards: [board], library: nil, folder: folder)
            case .library:
                let library = try decoder.decode(AppData.self, from: raw)
                return ImportedArchive(manifest: manifest, boards: library.boards, library: library, folder: folder)
            }
        } catch let error as ArchiveError {
            try? fm.removeItem(at: folder)
            throw error
        } catch {
            try? fm.removeItem(at: folder)
            throw ArchiveError.damaged
        }
    }

    /// 附件名只能是单纯的文件名
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".." && !name.hasPrefix(".")
    }

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "TaskBoard.ArchiveIO", code: Int(process.terminationStatus))
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Board {
    /// 复制一份使用全新 ID 的看板（列表、卡片、标签、清单项、附件都换新 ID，并重新建立关联）。
    /// `copyAttachment` 负责复制附件文件，返回 nil 表示附件缺失、跳过。
    func reidentified(copyAttachment: (Attachment) -> Attachment?) -> Board {
        var columnMap: [UUID: UUID] = [:]
        var labelMap: [UUID: UUID] = [:]
        var copy = self
        copy.id = UUID()
        copy.columns = columns.map { column in
            var c = column
            c.id = UUID()
            columnMap[column.id] = c.id
            return c
        }
        copy.labels = labels.map { label in
            var l = label
            l.id = UUID()
            labelMap[label.id] = l.id
            return l
        }
        copy.cards = cards.map { card in
            var c = card
            c.id = UUID()
            c.columnID = card.columnID.flatMap { columnMap[$0] }
            c.labelIDs = card.labelIDs.compactMap { labelMap[$0] }
            c.checklist = card.checklist.map { item in
                var i = item
                i.id = UUID()
                return i
            }
            c.attachments = card.attachments.compactMap(copyAttachment)
            return c
        }
        return copy
    }
}

/// 导入完成后的统计
struct ImportSummary {
    var boards = 0
    var cards = 0
    var attachments = 0
    var missingAttachments = 0

    var message: String {
        var text = String(localized: "已导入 \(boards) 个看板、\(cards) 张卡片、\(attachments) 个附件。")
        if missingAttachments > 0 {
            text += "\n" + String(localized: "有 \(missingAttachments) 个附件在文件中缺失，已跳过。")
        }
        return text
    }
}
