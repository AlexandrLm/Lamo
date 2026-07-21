import Foundation
import SwiftData

/// Lightweight dependency injection container.
///
/// Provides shared service instances with protocol-based abstractions
/// for testability. Backward-compatible with existing singleton access patterns.
///
/// Usage:
/// ```swift
/// // Production
/// let container = ServiceContainer.live
/// let memory = container.memoryService
///
/// // Testing
/// let mock = ServiceContainer.mock
/// ```
@MainActor
final class ServiceContainer {
    // MARK: - Shared

    /// The live container used by the app. Replace with `.mock` in tests.
    @MainActor static let live = ServiceContainer()

    /// Empty mock container for tests — all services are no-ops.
    @MainActor static let mock = ServiceContainer(
        memoryService: MockMemoryService(),
        downloadManager: MockDownloadManager()
    )

    // MARK: - Services

    let memoryService: MemoryServiceProtocol
    let downloadManager: DownloadManagerProtocol

    // MARK: - Init

    init(
        memoryService: MemoryServiceProtocol = MemoryService.shared,
        downloadManager: DownloadManagerProtocol = DownloadManager.shared
    ) {
        self.memoryService = memoryService
        self.downloadManager = downloadManager
    }
}

// MARK: - Protocols

/// Protocol for semantic memory operations.
@MainActor
protocol MemoryServiceProtocol: AnyObject {
    var isEnabled: Bool { get set }
    func pruneOldEntries(olderThan days: Int)
    func buildFullSystemPrompt(base: String, conversationID: UUID?) -> String
    func buildMemoryContext() -> String
    var currentConversationID: UUID? { get set }
}

/// Protocol for model download operations.
@MainActor
protocol DownloadManagerProtocol: AnyObject {
    // Reserved for future extraction of DownloadManager behind a protocol
}

// MARK: - Default Conformances

extension MemoryService: MemoryServiceProtocol {}

extension DownloadManager: DownloadManagerProtocol {}

// MARK: - Test Doubles

@MainActor
private final class MockMemoryService: MemoryServiceProtocol {
    var isEnabled: Bool = false
    func pruneOldEntries(olderThan days: Int) {}
    func buildFullSystemPrompt(base: String, conversationID: UUID?) -> String { base }
    func buildMemoryContext() -> String { "" }
    var currentConversationID: UUID?
}

@MainActor
private final class MockDownloadManager: DownloadManagerProtocol {}
