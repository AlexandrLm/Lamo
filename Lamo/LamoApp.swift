import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    @State private var hasSetupMemory = false

    init() {
        _ = DownloadManager.shared

        Task {
            await ProviderManager.shared.initializeEngineIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
                .onAppear {
                    if !hasSetupMemory {
                        hasSetupMemory = true
                        MemoryService.shared.pruneOldEntries(olderThan: 90)
                    }
                }
        }
        .modelContainer(for: [Conversation.self, Message.self, MemoryEntry.self])
    }
}
