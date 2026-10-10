import SwiftUI
import AppKit

struct BackupsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var backups: [BackupInfo] = []
    @State private var summaries: [URL: String] = [:]
    @State private var restoring: BackupInfo?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("备份", systemImage: "clock.arrow.circlepath")
                    .font(.title3.bold())
                Spacer()
                Text("每天自动备份一次，保留最近 \(Store.maxBackups) 份")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if backups.isEmpty {
                ContentUnavailableView("还没有备份", systemImage: "clock.arrow.circlepath",
                                       description: Text("应用每天会自动备份一次，也可以点击“立即备份”"))
                    .frame(maxHeight: .infinity)
            } else {
                List(backups) { backup in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: backup))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                                if let label = label(for: backup) {
                                    Text(label)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                }
                            }
                            Text(summaries[backup.url] ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复…") { restoring = backup }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button {
                    store.backupNow()
                    reload()
                } label: {
                    Label("立即备份", systemImage: "plus")
                }
                Button("在 Finder 中显示") {
                    NSWorkspace.shared.open(Store.backupsURL)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 420, idealHeight: 500)
        .onAppear(perform: reload)
        .confirmationDialog(
            "从这个备份恢复吗？",
            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            titleVisibility: .visible
        ) {
            Button("恢复") {
                guard let backup = restoring else { return }
                if store.restore(from: backup) {
                    dismiss()
                } else {
                    errorMessage = "这个备份文件无法读取。"
                }
            }
        } message: {
            Text("当前数据会先自动备份，恢复后也可以用 ⌘Z 撤销。")
        }
        .alert("恢复失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        backups = Store.listBackups()
        let list = backups
        DispatchQueue.global(qos: .userInitiated).async {
            var result: [URL: String] = [:]
            for backup in list {
                if let data = Store.readBackup(backup) {
                    let cards = data.boards.reduce(0) { $0 + $1.cards.count }
                    result[backup.url] = "\(data.boards.count) 个看板 · \(cards) 张卡片"
                } else {
                    result[backup.url] = "无法读取"
                }
            }
            DispatchQueue.main.async { summaries = result }
        }
    }

    private func label(for backup: BackupInfo) -> String? {
        switch backup.note {
        case nil: return nil
        case "manual": return "手动"
        case "before-restore": return "恢复前"
        case "unreadable": return "无法读取的原文件"
        case let other?: return other
        }
    }

    private func icon(for backup: BackupInfo) -> String {
        switch backup.note {
        case "manual": return "hand.tap"
        case "before-restore": return "arrow.uturn.backward"
        case "unreadable": return "exclamationmark.triangle"
        default: return "clock"
        }
    }
}
