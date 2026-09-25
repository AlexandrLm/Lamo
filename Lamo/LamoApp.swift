import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    @State private var hasSetupMemory = false
    /// App-wide container, created explicitly so MemoryService can bind its
    /// model context once at launch (instead of being rebound by every ChatViewModel init).
    private let container: ModelContainer

    init() {
        // Same schema as the previous .modelContainer(for:) modifier; the modifier
        // also traps on failure, so try! keeps equivalent behavior.
        container = try! ModelContainer(for: Conversation.self, Message.self, MemoryEntry.self)
        MemoryService.shared.setModelContext(container.mainContext)

        _ = DownloadManager.shared

        Task {
            await ProviderManager.shared.initializeEngineIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    if !hasSetupMemory {
                        hasSetupMemory = true
                        MemoryService.shared.pruneOldEntries(olderThan: 90)
                    }
                }
        }
        .modelContainer(container)
    }
}
