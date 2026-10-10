import Foundation
import AppKit

/// 界面语言。选择后写入应用自己的 AppleLanguages，重新启动后生效
/// （与“系统设置 → 通用 → 语言与地区 → App”中的设置是同一个值）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    /// 语言名称用各自的语言显示，方便在任何界面语言下找到自己的语言
    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }

    private static let key = "AppleLanguages"

    /// 当前保存的选择（不一定是正在使用的语言，修改后需要重新启动）
    static var saved: AppLanguage {
        guard let first = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String],
              let code = first.first else { return .system }
        return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
    }

    func save() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }

    /// 启动时保存的选择，用于判断修改后是否需要重新启动
    static let atLaunch = AppLanguage.saved

    /// 正在使用的界面语言
    static var active: AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .simplifiedChinese
    }
}

enum AppLocale {
    /// 与界面语言一致的 Locale（语言跟随应用，地区跟随系统），用于日期和时间格式
    static let current: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        var components = Locale.Components(identifier: language)
        components.region = Locale.current.region
        return Locale(components: components)
    }()
}

extension Date {
    /// 使用界面语言格式化日期
    func appFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(AppLocale.current))
    }
}

enum AppRelauncher {
    /// 重新启动应用（用于切换语言）
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
