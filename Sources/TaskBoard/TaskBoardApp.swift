import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TaskBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("任务看板", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建看板") { store.addBoard() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("立即保存") { store.saveNow() }
                    .keyboardShortcut("s")
                Button("在 Finder 中显示数据文件夹") {
                    NSWorkspace.shared.activateFileViewerSelecting([Store.dataURL])
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var renamingBoardID: UUID?
    @State private var renameText = ""
    @State private var deletingBoardID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $store.data.selectedBoardID) {
                Section("看板") {
                    ForEach(store.data.boards) { board in
                        Label {
                            Text(board.name)
                        } icon: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(board.background.color)
                                .frame(width: 16, height: 16)
                        }
                        .tag(board.id)
                        .contextMenu {
                            Button("重命名…") { beginRename(board) }
                            Divider()
                            Button("删除看板…", role: .destructive) { deletingBoardID = board.id }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let id = store.addBoard()
                    if let board = store.board(id) { beginRename(board) }
                } label: {
                    Label("新建看板", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let id = store.data.selectedBoardID, store.board(id) != nil {
                BoardView(boardID: id).id(id)
            } else {
                ContentUnavailableView("没有选中的看板", systemImage: "rectangle.split.3x1",
                                       description: Text("在左侧选择或新建一个看板"))
            }
        }
        .alert("重命名看板", isPresented: Binding(
            get: { renamingBoardID != nil },
            set: { if !$0 { renamingBoardID = nil } }
        )) {
            TextField("看板名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let id = renamingBoardID { store.renameBoard(id, to: renameText) }
            }
        }
        .confirmationDialog(
            "确定删除看板「\(store.board(deletingBoardID)?.name ?? "")」吗？",
            isPresented: Binding(get: { deletingBoardID != nil }, set: { if !$0 { deletingBoardID = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = deletingBoardID { store.deleteBoard(id) }
            }
        } message: {
            Text("看板中的所有卡片和附件（包括归档）都会被永久删除。")
        }
    }

    private func beginRename(_ board: Board) {
        renameText = board.name
        renamingBoardID = board.id
    }
}
