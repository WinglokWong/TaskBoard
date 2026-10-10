import Foundation
import UniformTypeIdentifiers

// 数据模型说明：
// 所有模型都使用容错解码（见文件末尾的 Decodable 扩展）。新增字段时务必在解码扩展里给出默认值，
// 这样旧版本保存的 data.json 依然可以被读取，而不会因为缺少字段导致整个文件解析失败。

struct Attachment: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 存储在附件目录中的文件名
    var fileName: String
    /// 用户导入时的原始文件名
    var originalName: String

    var url: URL { Store.attachmentsURL.appendingPathComponent(fileName) }

    var isImage: Bool {
        let ext = (fileName as NSString).pathExtension
        return UTType(filenameExtension: ext)?.conforms(to: .image) ?? false
    }
}

struct CardLabel: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 可以为空：只用颜色区分
    var name: String = ""
    var color: RGBAColor

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if let colorName = Palette.name(for: color) {
            return String(localized: "\(colorName)色标签", comment: "没有名称的标签，以颜色命名，例如“绿色标签”")
        }
        return String(localized: "未命名标签")
    }
}

struct ChecklistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var isDone = false
}

struct Card: Identifiable, Codable, Hashable {
    var id = UUID()
    var columnID: UUID?
    var title: String
    var details: String = ""
    var attachments: [Attachment] = []
    var checklist: [ChecklistItem] = []
    var labelIDs: [UUID] = []
    var color: RGBAColor? = nil
    var isDone = false
    var isArchived = false
    var dueDate: Date? = nil
    /// 提前多少分钟提醒；nil 表示不提醒
    var reminderMinutes: Int? = nil
    var createdAt = Date()
    var archivedAt: Date? = nil
    /// 标记完成的时间，用于自动归档
    var completedAt: Date? = nil

    var coverImage: Attachment? { attachments.first(where: \.isImage) }

    var reminderDate: Date? {
        guard let dueDate, let reminderMinutes else { return nil }
        return dueDate.addingTimeInterval(-Double(reminderMinutes) * 60)
    }

    var checklistDoneCount: Int { checklist.filter(\.isDone).count }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || details.localizedCaseInsensitiveContains(query)
            || checklist.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }
}

struct ReminderOption: Identifiable {
    let minutes: Int?
    let title: String
    var id: Int { minutes ?? -1 }

    static let all: [ReminderOption] = [
        .init(minutes: nil, title: String(localized: "不提醒")),
        .init(minutes: 0, title: String(localized: "到期时")),
        .init(minutes: 15, title: String(localized: "提前 15 分钟")),
        .init(minutes: 60, title: String(localized: "提前 1 小时")),
        .init(minutes: 24 * 60, title: String(localized: "提前 1 天")),
    ]
}

struct AutoArchiveOption: Identifiable {
    let days: Int?
    let title: String
    var id: Int { days ?? -1 }

    static let all: [AutoArchiveOption] = [
        .init(days: nil, title: String(localized: "关闭")),
        .init(days: 1, title: String(localized: "完成 1 天后")),
        .init(days: 3, title: String(localized: "完成 3 天后")),
        .init(days: 7, title: String(localized: "完成 7 天后")),
        .init(days: 30, title: String(localized: "完成 30 天后")),
    ]
}

struct BoardColumn: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: RGBAColor? = nil
}

struct Board: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var background: RGBAColor
    var columns: [BoardColumn]
    /// 所有卡片（包括已归档）。在同一列内，数组顺序即显示顺序。
    var cards: [Card] = []
    var labels: [CardLabel] = Board.defaultLabels
    /// 已完成的卡片在多少天后自动归档；nil 表示关闭
    var autoArchiveDays: Int? = nil

    func columnName(_ id: UUID?) -> String? {
        columns.first(where: { $0.id == id })?.name
    }

    /// 卡片上的标签，按看板中标签的顺序排列，忽略已删除的标签
    func labels(of card: Card) -> [CardLabel] {
        labels.filter { card.labelIDs.contains($0.id) }
    }

    static var defaultLabels: [CardLabel] {
        ["green", "yellow", "orange", "red", "purple", "blue"].compactMap { key in
            Palette.color(key).map { CardLabel(color: $0) }
        }
    }
}

struct AppData: Codable, Equatable {
    /// 数据格式版本。修改数据结构时递增。
    static let currentSchemaVersion = 4

    var schemaVersion = AppData.currentSchemaVersion
    var boards: [Board]
    var selectedBoardID: UUID?

    var attachmentFileNames: Set<String> {
        Set(boards.flatMap { $0.cards.flatMap { $0.attachments.map(\.fileName) } })
    }

    /// 自动归档：在开启了自动归档的看板中，归档完成时间超过设定天数的卡片。
    /// 没有完成时间的已完成卡片（升级前完成的）从现在开始计时。返回是否有改动。
    mutating func applyAutoArchive(now: Date) -> Bool {
        var changed = false
        for bi in boards.indices {
            guard let days = boards[bi].autoArchiveDays else { continue }
            let limit = Double(days) * 24 * 3600
            for ci in boards[bi].cards.indices {
                let card = boards[bi].cards[ci]
                guard card.isDone, !card.isArchived else { continue }
                if let completed = card.completedAt {
                    if now.timeIntervalSince(completed) >= limit {
                        boards[bi].cards[ci].isArchived = true
                        boards[bi].cards[ci].archivedAt = now
                        changed = true
                    }
                } else {
                    boards[bi].cards[ci].completedAt = now
                    changed = true
                }
            }
        }
        return changed
    }

    static var sample: AppData {
        // 示例看板使用当前界面语言
        var board = Board.makeDefault(name: String(localized: "我的看板"))
        let todo = board.columns[0].id, doing = board.columns[1].id, done = board.columns[2].id
        board.cards = [
            Card(columnID: todo, title: String(localized: "欢迎使用任务看板 👋"),
                 details: String(localized: "• 点击卡片可编辑标题、内容、颜色和附件\n• 拖拽卡片可在列表之间移动\n• 点击左侧圆圈标记完成\n• 右键卡片可快速设置颜色、归档或删除\n• 误操作可以用 ⌘Z 撤销")),
            Card(columnID: todo, title: String(localized: "双击列表名称可以重命名"), color: Palette.color("yellow")),
            Card(columnID: doing, title: String(localized: "试试给卡片添加一张图片附件"), color: Palette.color("lightBlue")),
            Card(columnID: done, title: String(localized: "点击工具栏的调色板修改背景颜色"), isDone: true),
        ]
        return AppData(boards: [board], selectedBoardID: board.id)
    }
}

extension Board {
    static func makeDefault(name: String) -> Board {
        Board(
            name: name,
            background: RGBAColor(hex: 0x0C66E4),
            columns: [
                BoardColumn(name: String(localized: "待办")),
                BoardColumn(name: String(localized: "进行中")),
                BoardColumn(name: String(localized: "已完成")),
            ]
        )
    }
}
