import SwiftUI
import Combine
import Sparkle

/// Sparkle 自动更新。只有从打包好的 .app 运行（Info.plist 中有 SUFeedURL）时才启用。
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet {
            if let updater = controller?.updater, updater.automaticallyChecksForUpdates != automaticallyChecks {
                updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }

    var isAvailable: Bool { controller != nil }

    init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

struct UpdateCommands: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button("检查更新…") { updater.checkForUpdates() }
            .disabled(!updater.isAvailable || !updater.canCheckForUpdates)
        Toggle("自动检查更新", isOn: $updater.automaticallyChecks)
            .disabled(!updater.isAvailable)
    }
}
