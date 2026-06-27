import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    init() {
        // Pre-initialize the LiteRT-LM engine in background.
        // This avoids blocking the UI on first inference.
        Task {
            await ProviderManager.shared.initializeEngineIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .modelContainer(for: [Conversation.self, Message.self])
    }
}
