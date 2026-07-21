import Foundation
import os

enum LamoLogger {
    /// Centralized subsystem identifier. Use `LamoLogger.subsystem` instead of hardcoding "com.lamo".
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.lamo"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let download = Logger(subsystem: subsystem, category: "download")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
