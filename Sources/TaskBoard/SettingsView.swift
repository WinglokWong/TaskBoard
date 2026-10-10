import SwiftUI
import AppKit

/// UserDefaults 中的偏好设置键（偏好属于这台 Mac，不写入 data.json）
enum SettingsKey {
    static let defaultReminderMinutes = "defaultReminderMinutes"   // -1 表示不提醒
    static let defaultDueMinutes = "defaultDueMinutes"             // 一天中的分钟数，默认 9:00
    static let maxBackups = "maxBackups"
}

enum DueDefaults {
    static var reminderMinutes: Int? {
        let stored = UserDefaults.standard.object(forKey: SettingsKey.defaultReminderMinutes) as? Int ?? 0
        return stored < 0 ? nil : stored
    }

    /// 新截止日期的默认值：明天的默认时间
    static func nextDueDate(from now: Date = Date()) -> Date {
        let minutes = UserDefaults.standard.object(forKey: SettingsKey.defaultDueMinutes) as? Int ?? 9 * 60
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return cal.date(byAdding: .minute, value: minutes, to: tomorrow) ?? tomorrow
    }
}

struct SettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("通用", systemImage: "gearshape") }
            DataSettings()
                .tabItem { Label("数据", systemImage: "externaldrive") }
            UpdateSettings(updater: updater)
                .tabItem { Label("更新", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @State private var language = AppLanguage.saved

    @AppStorage(SettingsKey.defaultReminderMinutes) private var reminderMinutes = 0
    @AppStorage(SettingsKey.defaultDueMinutes) private var dueMinutes = 9 * 60

    var body: some View {
        Form {
            Section {
                Picker("界面语言", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: language) { _, newValue in newValue.save() }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("重新启动后生效。")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即重新启动") { AppRelauncher.relaunch() }
                    }
                }
            } footer: {
                Text("也可以在“系统设置 → 通用 → 语言与地区 → App”中为任务看板单独设置语言。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("新截止日期的默认值") {
                DatePicker("默认时间", selection: Binding(
                    get: {
                        Calendar.current.date(byAdding: .minute, value: dueMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        dueMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)
                Picker("默认提醒", selection: $reminderMinutes) {
                    ForEach(ReminderOption.all) { Text($0.title).tag($0.minutes ?? -1) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataSettings: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.maxBackups) private var maxBackups = 30

    var body: some View {
        Form {
            Section {
                LabeledContent("数据位置") {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([Store.dataURL])
                    }
                }
            } footer: {
                Text(Store.rootURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("备份") {
                Picker("保留备份", selection: $maxBackups) {
                    ForEach([10, 30, 60, 100], id: \.self) { Text("最近 \($0) 份").tag($0) }
                }
                HStack {
                    Button("立即备份") { store.backupNow() }
                    Button("从备份恢复…") {
                        openWindow(id: "main")
                        store.showBackups = true
                    }
                }
            }

            Section {
                HStack {
                    Button("导出全部数据…") { store.exportAllData() }
                    Button("导入…") {
                        openWindow(id: "main")
                        store.chooseImportFile()
                    }
                }
            } header: {
                Text("导入与导出")
            } footer: {
                Text("导出的 .taskboard 文件包含看板和附件，可以在另一台 Mac 上导入。单个看板可以在看板的设置菜单中导出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            LabeledContent("当前版本", value: version)
            Toggle("自动检查更新", isOn: $updater.automaticallyChecks)
                .disabled(!updater.isAvailable)
            HStack {
                Spacer()
                Button("立即检查更新") { updater.checkForUpdates() }
                    .disabled(!updater.isAvailable || !updater.canCheckForUpdates)
            }
            if !updater.isAvailable {
                Text("从源码运行时不提供自动更新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
