import Foundation
import os

enum LamoLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.lamo"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let download = Logger(subsystem: subsystem, category: "download")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
