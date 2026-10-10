import Foundation

/// 截止日期分组，用于筛选和“即将到期”视图
enum DueCategory: Int, CaseIterable, Identifiable {
    case overdue, today, tomorrow, thisWeek, later

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overdue: return String(localized: "已过期")
        case .today: return String(localized: "今天")
        case .tomorrow: return String(localized: "明天")
        case .thisWeek: return String(localized: "7 天内")
        case .later: return String(localized: "以后")
        }
    }

    static func of(_ due: Date, now: Date = Date()) -> DueCategory {
        let cal = Calendar.current
        if due < now { return .overdue }
        if cal.isDateInToday(due) { return .today }
        if cal.isDateInTomorrow(due) { return .tomorrow }
        let startOfToday = cal.startOfDay(for: now)
        if let limit = cal.date(byAdding: .day, value: 7, to: startOfToday), due < limit { return .thisWeek }
        return .later
    }
}

struct BoardFilter: Equatable {
    enum Status: String, CaseIterable, Identifiable {
        case all, open, done
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return String(localized: "全部")
            case .open: return String(localized: "未完成")
            case .done: return String(localized: "已完成")
            }
        }
    }

    enum Due: String, CaseIterable, Identifiable {
        case any, overdue, today, week, none
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return String(localized: "不限")
            case .overdue: return String(localized: "已过期")
            case .today: return String(localized: "今天到期")
            case .week: return String(localized: "7 天内到期")
            case .none: return String(localized: "没有截止日期")
            }
        }
    }

    var labelIDs: Set<UUID> = []
    var status: Status = .all
    var due: Due = .any

    var isActive: Bool { !labelIDs.isEmpty || status != .all || due != .any }
    var activeCount: Int { (labelIDs.isEmpty ? 0 : 1) + (status == .all ? 0 : 1) + (due == .any ? 0 : 1) }

    func matches(_ card: Card, now: Date = Date()) -> Bool {
        if !labelIDs.isEmpty && labelIDs.isDisjoint(with: card.labelIDs) { return false }
        switch status {
        case .all: break
        case .open: if card.isDone { return false }
        case .done: if !card.isDone { return false }
        }
        switch due {
        case .any:
            return true
        case .none:
            return card.dueDate == nil
        case .overdue:
            guard let d = card.dueDate else { return false }
            return !card.isDone && d < now
        case .today:
            guard let d = card.dueDate else { return false }
            return Calendar.current.isDateInToday(d)
        case .week:
            guard let d = card.dueDate else { return false }
            let cat = DueCategory.of(d, now: now)
            return cat != .later && (cat != .overdue || Calendar.current.isDateInToday(d))
        }
    }
}
