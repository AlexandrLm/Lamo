import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    init() {
        // Pre-initialize DownloadManager to handle background sessions
        _ = DownloadManager.shared

        Task {
            await ProviderManager.shared.initializeEngineIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
