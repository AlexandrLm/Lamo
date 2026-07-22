import Foundation
import os

enum LamoLogger {
    /// Centralized subsystem identifier. Uses CFBundle to avoid @MainActor isolation.
    nonisolated static let subsystem: String = {
        if let id = CFBundleGetIdentifier(CFBundleGetMainBundle()) as String? {
            return id
        }
        return "com.lamo"
    }()

    static let general = Logger(subsystem: subsystem, category: "general")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let download = Logger(subsystem: subsystem, category: "download")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
