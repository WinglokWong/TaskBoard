import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 在窗口准备好之前收到的待打开文件
    static var pendingOpenURLs: [URL] = []
    static var openHandler: ((URL) -> Void)? {
        didSet {
            guard let openHandler else { return }
            pendingOpenURLs.forEach(openHandler)
            pendingOpenURLs.removeAll()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppLanguage.atLaunch
        NotificationManager.shared.setUp()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 在 Finder 中双击 .taskboard 文件
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "taskboard" {
            if let handler = Self.openHandler { handler(url) } else { Self.pendingOpenURLs.append(url) }
        }
    }
}

@main
struct TaskBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        Window("任务看板", id: "main") {
            ContentView()
                .environment(store)
                .environment(\.locale, AppLocale.current)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                UpdateCommands(updater: updater)
            }
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
                Divider()
                Button("导入…") { store.chooseImportFile() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("导出当前看板…") {
                    if let id = store.data.selectedBoardID { store.exportBoard(id) }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(store.showingUpcoming || store.board(store.data.selectedBoardID) == nil)
                Button("导出全部数据…") { store.exportAllData() }
                Divider()
                Button("立即备份") { store.backupNow() }
                Button("从备份恢复…") { store.showBackups = true }
            }
            CommandGroup(replacing: .help) {
                Button("键盘快捷键") { store.showShortcuts = true }
                    .keyboardShortcut("/", modifiers: .command)
            }
        }

        Settings {
            SettingsView(updater: updater)
                .environment(store)
                .environment(\.locale, AppLocale.current)
        }
    }
}

enum SidebarItem: Hashable {
    case upcoming
    case board(UUID)
}

struct ContentView: View {
    @Environment(Store.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var renamingBoardID: UUID?
    @State private var renameText = ""
    @State private var deletingBoardID: UUID?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    Label("即将到期", systemImage: "calendar.badge.clock")
                        .badge(urgentCount)
                        .tag(SidebarItem.upcoming)
                        .help("已过期和今天到期的未完成卡片数")
                }
                Section("看板") {
                    ForEach(store.data.boards) { board in
                        Label {
                            Text(board.name)
                        } icon: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(board.background.color)
                                .frame(width: 16, height: 16)
                        }
                        .tag(SidebarItem.board(board.id))
                        .contextMenu {
                            Button("重命名…") { beginRename(board) }
                            Button("导出看板…") { store.exportBoard(board.id) }
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
            if store.showingUpcoming {
                UpcomingView()
            } else if let id = store.data.selectedBoardID, store.board(id) != nil {
                BoardView(boardID: id).id(id)
            } else {
                ContentUnavailableView("没有选中的看板", systemImage: "rectangle.split.3x1",
                                       description: Text("在左侧选择或新建一个看板"))
            }
        }
        .onAppear {
            store.undoManager = undoManager
            AppDelegate.openHandler = { [weak store] url in store?.prepareImport(url) }
            NotificationManager.shared.onOpenCard = { [weak store] boardID, cardID in
                store?.requestOpen(cardID: cardID, in: boardID)
            }
        }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
        .sheet(isPresented: $store.showShortcuts) {
            ShortcutsView()
        }
        .sheet(isPresented: $store.showBackups) {
            BackupsView().environment(store)
        }
        .modifier(TransferDialogs())
        .alert("数据读取失败", isPresented: Binding(
            get: { store.startupMessage != nil },
            set: { if !$0 { store.startupMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(store.startupMessage ?? "")
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

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: {
                if store.showingUpcoming { return .upcoming }
                return store.data.selectedBoardID.map { .board($0) }
            },
            set: { item in
                switch item {
                case .upcoming:
                    store.showingUpcoming = true
                case .board(let id):
                    store.showingUpcoming = false
                    if store.data.selectedBoardID != id { store.data.selectedBoardID = id }
                case nil:
                    break
                }
            }
        )
    }

    /// 已过期或今天到期的未完成卡片数
    private var urgentCount: Int {
        let now = Date()
        return store.data.boards.reduce(0) { total, board in
            total + board.cards.filter { card in
                guard !card.isDone, !card.isArchived, let due = card.dueDate else { return false }
                return due < now || Calendar.current.isDateInToday(due)
            }.count
        }
    }

    private func beginRename(_ board: Board) {
        renameText = board.name
        renamingBoardID = board.id
    }
}
