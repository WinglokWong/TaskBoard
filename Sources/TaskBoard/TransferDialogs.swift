import SwiftUI
import AppKit

/// 导入确认和导入 / 导出结果的对话框
struct TransferDialogs: ViewModifier {
    @Environment(Store.self) private var store

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { store.importCandidate != nil },
                    set: { if !$0 && store.importCandidate != nil { store.cancelImport() } }
                ),
                titleVisibility: .visible,
                presenting: store.importCandidate
            ) { archive in
                if archive.isLibrary {
                    Button("作为新看板添加") { store.importAsNewBoards(archive) }
                    Button("替换全部数据", role: .destructive) { store.replaceAllData(with: archive) }
                } else {
                    Button("导入") { store.importAsNewBoards(archive) }
                }
                Button("取消", role: .cancel) { store.cancelImport() }
            } message: { archive in
                if archive.isLibrary {
                    Text("包含 \(archive.boards.count) 个看板、\(archive.cardCount) 张卡片。“替换全部数据”会用文件内容取代当前所有看板，替换前会自动备份，也可以用 ⌘Z 撤销。")
                } else {
                    Text("将作为新看板加入，现有看板不受影响。包含 \(archive.cardCount) 张卡片。")
                }
            }
            .alert(
                store.transferAlert?.title ?? "",
                isPresented: Binding(
                    get: { store.transferAlert != nil },
                    set: { if !$0 { store.transferAlert = nil } }
                ),
                presenting: store.transferAlert
            ) { alert in
                if let url = alert.revealURL {
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                Button("好", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
    }

    private var confirmationTitle: String {
        guard let archive = store.importCandidate else { return "" }
        if archive.isLibrary { return String(localized: "导入全部数据") }
        return String(localized: "导入看板「\(archive.boards.first?.name ?? "")」？")
    }
}
