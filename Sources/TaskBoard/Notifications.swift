import Foundation
import AppKit
import UserNotifications

/// 管理卡片截止日期的本地提醒
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// 用户点击通知时打开对应卡片（boardID, cardID）
    var onOpenCard: ((UUID, UUID) -> Void)?

    private let identifierPrefix = "taskboard.due."
    /// 系统对每个应用的待发送通知数量有限制，只安排最近的这些
    private let maxPending = 60

    /// 不在 .app 包内运行（例如 `swift run`）时，通知中心不可用
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func setUp() {
        center?.delegate = self
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 通知权限是否被用户关闭
    func checkDenied(_ completion: @escaping (Bool) -> Void) {
        guard let center else { return completion(false) }
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus == .denied) }
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 根据当前数据重新安排所有提醒
    func reschedule(for data: AppData) {
        guard let center else { return }
        let now = Date()
        var requests: [(date: Date, request: UNNotificationRequest)] = []
        for board in data.boards {
            for card in board.cards where !card.isDone && !card.isArchived {
                guard let fire = card.reminderDate, let due = card.dueDate, fire > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = card.title.isEmpty ? "卡片到期" : card.title
                content.body = "截止时间：\(DueFormat.long(due)) · \(board.name)"
                content.sound = .default
                content.userInfo = ["boardID": board.id.uuidString, "cardID": card.id.uuidString]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifierPrefix + card.id.uuidString, content: content, trigger: trigger)
                requests.append((fire, request))
            }
        }
        requests.sort { $0.date < $1.date }
        let toAdd = requests.prefix(maxPending).map(\.request)
        let prefix = identifierPrefix

        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard !toAdd.isEmpty else { return }
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                toAdd.forEach { center.add($0) }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let b = (info["boardID"] as? String).flatMap(UUID.init(uuidString:)),
           let c = (info["cardID"] as? String).flatMap(UUID.init(uuidString:)) {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                self.onOpenCard?(b, c)
            }
        }
        completionHandler()
    }
}

enum DueFormat {
    private static let zh = Locale(identifier: "zh_CN")

    /// 卡片上的简短格式，例如「今天 14:00」「10月12日 09:00」
    static func short(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(zh))
        if cal.isDateInToday(date) { return "今天 \(time)" }
        if cal.isDateInTomorrow(date) { return "明天 \(time)" }
        if cal.isDateInYesterday(date) { return "昨天 \(time)" }
        if cal.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.defaultDigits).day().locale(zh)) + " \(time)"
        }
        return date.formatted(.dateTime.year().month(.defaultDigits).day().locale(zh)) + " \(time)"
    }

    static func long(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.defaultDigits).day().weekday(.abbreviated).hour().minute().locale(zh))
    }
}
