import Foundation

enum LamoError: LocalizedError, Equatable {
    case modelNotFound(String)
    case engineInitFailed(String)
    case modelCorrupted(String)
    case insufficientMemory(available: Double, required: Double)
    case insufficientDiskSpace
    case modelTooSmall(Double)
    case noModelAvailable
    case modelStuckInLoop
    case foundationModelsUnavailable(String)
    case foundationModelsError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): return String(localized: "Model not found: \(path)")
        case .engineInitFailed(let reason): return String(localized: "Engine initialization failed: \(reason)")
        case .modelCorrupted(let path): return String(localized: "Model file corrupted: \(path)")
        case .insufficientMemory(let avail, let req): return String(localized: "Insufficient memory. Available: \(String(format: "%.1f", avail))GB, required: \(String(format: "%.1f", req))GB")
        case .insufficientDiskSpace: return String(localized: "Not enough storage. Free up at least 1 GB.")
        case .modelTooSmall(let size): return String(localized: "Model file too small (\(String(format: "%.2f", size)) GB). Re-download recommended.")
        case .noModelAvailable: return String(localized: "No model available. Download a model in Settings.")
        case .modelStuckInLoop: return String(localized: "Model stuck in a loop. Try rephrasing your message or adjusting temperature in Settings.")
        case .foundationModelsUnavailable(let reason): return String(localized: "Apple Intelligence unavailable: \(reason)")
        case .foundationModelsError(let message): return String(localized: "Apple Intelligence error: \(message)")
        }
    }
}
