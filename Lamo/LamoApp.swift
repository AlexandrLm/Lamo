import SwiftUI
import SwiftData

@main
struct LamoApp: App {
    @State private var hasSetupMemory = false
    @State private var setupTask: Task<Void, Never>?
    /// App-wide container, created explicitly so MemoryService can bind its
    /// model context once at launch (instead of being rebound by every ChatViewModel init).
    private let container: ModelContainer

    init() {
        // Same schema as the previous .modelContainer(for:) modifier, but with
        // a graceful fallback instead of trapping on failure (e.g. corrupt store).
        do {
            container = try ModelContainer(for: Conversation.self, Message.self, MemoryEntry.self)
        } catch {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: Conversation.self, Message.self, MemoryEntry.self, configurations: config) {
                container = fallback
            } else {
                fatalError("ModelContainer init failed even in-memory: \(error)")
            }
        }
        MemoryService.shared.setModelContext(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .task {
                    // Runs after the first frame; cancelled automatically on view teardown.
                    setupTask?.cancel()
                    setupTask = Task {
                        _ = DownloadManager.shared
                        await ProviderManager.shared.initializeEngineIfNeeded()
                        if !Task.isCancelled, !hasSetupMemory {
                            hasSetupMemory = true
                            MemoryService.shared.pruneOldEntries(olderThan: 90)
                        }
                    }
                    await setupTask?.value
                }
        }
        .modelContainer(container)
    }
}
