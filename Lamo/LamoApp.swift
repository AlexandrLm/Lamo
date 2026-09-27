import SwiftUI
import SwiftData
import os

@main
struct LamoApp: App {
    @State private var hasSetupMemory = false
    @State private var setupTask: Task<Void, Never>?
    /// App-wide container, created explicitly so MemoryService can bind its
    /// model context once at launch (instead of being rebound by every ChatViewModel init).
    private let container: ModelContainer

    private static let logger = Logger(subsystem: LamoLogger.subsystem, category: "app")

    init() {
        container = Self.makeContainer()
        MemoryService.shared.setModelContext(container.mainContext)
    }

    /// Build the persistent container with a real recovery path.
    ///
    /// Adding a non-optional attribute (for example `Conversation.isUntitled`)
    /// makes lightweight migration fail on stores written by older builds, with
    /// "missing attribute values on mandatory destination attribute". Losing the
    /// database silently is worse than losing one conversation history, so the
    /// unreadable store is moved aside and recreated, and the app keeps working.
    private static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Conversation.self, Message.self, MemoryEntry.self)
        } catch {
            logger.error("Persistent store failed to open: \(error.localizedDescription) — archiving and recreating")
            archiveStore()
            if let recreated = try? ModelContainer(for: Conversation.self, Message.self, MemoryEntry.self) {
                return recreated
            }
            // Last resort: keep the app usable for this session without crashing.
            let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(
                for: Conversation.self, Message.self, MemoryEntry.self, configurations: inMemory
            ) {
                return fallback
            }
            fatalError("ModelContainer init failed even in-memory: \(error)")
        }
    }

    /// Move the unusable store files aside so SwiftData can create a fresh one.
    private static func archiveStore() {
        let fm = FileManager.default
        guard let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true) else { return }
        let store = support.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: store.path) else { return }

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let backup = support.appendingPathComponent("default.store.corrupt-\(stamp)")
        try? fm.moveItem(at: store, to: backup)
        for suffix in ["-wal", "-shm"] {
            let sidecar = support.appendingPathComponent("default.store\(suffix)")
            try? fm.moveItem(at: sidecar, to: backup.appendingPathExtension(suffix.replacingOccurrences(of: "-", with: "")))
        }
        logger.notice("Unreadable store archived at \(backup.lastPathComponent)")
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
