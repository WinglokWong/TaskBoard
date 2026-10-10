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
        return Palette.name(for: color).map { "\($0)色标签" } ?? "未命名标签"
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
    var id: String { title }

    static let all: [ReminderOption] = [
        .init(minutes: nil, title: "不提醒"),
        .init(minutes: 0, title: "到期时"),
        .init(minutes: 15, title: "提前 15 分钟"),
        .init(minutes: 60, title: "提前 1 小时"),
        .init(minutes: 24 * 60, title: "提前 1 天"),
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

    func columnName(_ id: UUID?) -> String? {
        columns.first(where: { $0.id == id })?.name
    }

    /// 卡片上的标签，按看板中标签的顺序排列，忽略已删除的标签
    func labels(of card: Card) -> [CardLabel] {
        labels.filter { card.labelIDs.contains($0.id) }
    }

    static var defaultLabels: [CardLabel] {
        ["绿", "黄", "橙", "红", "紫", "蓝"].compactMap { name in
            Palette.color(named: name).map { CardLabel(color: $0) }
        }
    }
}

struct AppData: Codable, Equatable {
    /// 数据格式版本。修改数据结构时递增。
    static let currentSchemaVersion = 3

    var schemaVersion = AppData.currentSchemaVersion
    var boards: [Board]
    var selectedBoardID: UUID?

    var attachmentFileNames: Set<String> {
        Set(boards.flatMap { $0.cards.flatMap { $0.attachments.map(\.fileName) } })
    }

    static var sample: AppData {
        var board = Board.makeDefault(name: "我的看板")
        let todo = board.columns[0].id, doing = board.columns[1].id, done = board.columns[2].id
        board.cards = [
            Card(columnID: todo, title: "欢迎使用任务看板 👋",
                 details: "• 点击卡片可编辑标题、内容、颜色和附件\n• 拖拽卡片可在列表之间移动\n• 点击左侧圆圈标记完成\n• 右键卡片可快速设置颜色、归档或删除\n• 误操作可以用 ⌘Z 撤销"),
            Card(columnID: todo, title: "双击列表名称可以重命名", color: Palette.color(named: "黄")),
            Card(columnID: doing, title: "试试给卡片添加一张图片附件", color: Palette.color(named: "浅蓝")),
            Card(columnID: done, title: "点击工具栏的调色板修改背景颜色", isDone: true),
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
                BoardColumn(name: "待办"),
                BoardColumn(name: "进行中"),
                BoardColumn(name: "已完成"),
            ]
        )
    }
}

/// 拖拽卡片时使用的字符串载荷
enum CardDrag {
    static let prefix = "taskboard-card:"

    static func encode(_ id: UUID) -> String { prefix + id.uuidString }

    static func decode(_ string: String) -> UUID? {
        guard string.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(string.dropFirst(prefix.count)))
    }
}

// MARK: - 容错解码

extension KeyedDecodingContainer {
    /// 字段缺失或类型不匹配时返回默认值，而不是让整个解码失败。
    /// 只用于标量字段；数组字段要用 decodeIfPresent，避免一个元素出错就把整个数组清空后保存覆盖。
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

extension Attachment {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        fileName = try c.decode(String.self, forKey: .fileName)
        originalName = c.value(.originalName, default: fileName)
    }
}

extension CardLabel {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "")
        color = c.value(.color, default: RGBAColor(hex: 0x8590A2))
    }
}

extension ChecklistItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        text = c.value(.text, default: "")
        isDone = c.value(.isDone, default: false)
    }
}

extension Card {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        columnID = c.value(.columnID, default: nil)
        title = c.value(.title, default: "")
        details = c.value(.details, default: "")
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        checklist = try c.decodeIfPresent([ChecklistItem].self, forKey: .checklist) ?? []
        labelIDs = c.value(.labelIDs, default: [])
        color = c.value(.color, default: nil)
        isDone = c.value(.isDone, default: false)
        isArchived = c.value(.isArchived, default: false)
        dueDate = c.value(.dueDate, default: nil)
        reminderMinutes = c.value(.reminderMinutes, default: nil)
        createdAt = c.value(.createdAt, default: Date())
        archivedAt = c.value(.archivedAt, default: nil)
    }
}

extension BoardColumn {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "未命名列表")
        color = c.value(.color, default: nil)
    }
}

extension Board {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "未命名看板")
        background = c.value(.background, default: RGBAColor(hex: 0x0C66E4))
        columns = try c.decodeIfPresent([BoardColumn].self, forKey: .columns) ?? []
        cards = try c.decodeIfPresent([Card].self, forKey: .cards) ?? []
        // 旧版本没有标签：给一套默认颜色标签
        labels = try c.decodeIfPresent([CardLabel].self, forKey: .labels) ?? Board.defaultLabels
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.value(.schemaVersion, default: 1)
        // boards 是唯一必须存在的字段：如果连它都读不到，说明文件确实损坏了
        boards = try c.decode([Board].self, forKey: .boards)
        selectedBoardID = c.value(.selectedBoardID, default: nil)
    }
}
