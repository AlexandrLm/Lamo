import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    init() {
        // Pre-initialize the LiteRT-LM engine in background.
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
