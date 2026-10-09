import Foundation
import UniformTypeIdentifiers

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

struct Card: Identifiable, Codable, Hashable {
    var id = UUID()
    var columnID: UUID?
    var title: String
    var details: String = ""
    var attachments: [Attachment] = []
    var color: RGBAColor? = nil
    var isDone = false
    var isArchived = false
    var createdAt = Date()
    var archivedAt: Date? = nil

    var coverImage: Attachment? { attachments.first(where: \.isImage) }
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

    func columnName(_ id: UUID?) -> String? {
        columns.first(where: { $0.id == id })?.name
    }
}

struct AppData: Codable {
    var boards: [Board]
    var selectedBoardID: UUID?

    static var sample: AppData {
        var board = Board.makeDefault(name: "我的看板")
        let todo = board.columns[0].id, doing = board.columns[1].id, done = board.columns[2].id
        board.cards = [
            Card(columnID: todo, title: "欢迎使用任务看板 👋",
                 details: "• 点击卡片可编辑标题、内容、颜色和附件\n• 拖拽卡片可在列表之间移动\n• 点击左侧圆圈标记完成\n• 右键卡片可快速设置颜色、归档或删除"),
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
