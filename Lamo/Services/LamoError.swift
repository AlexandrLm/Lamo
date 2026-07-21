import Foundation

enum LamoError: LocalizedError, Equatable {
    case modelNotFound(String)
    case engineInitFailed(String)
    case modelCorrupted(String)
    case insufficientMemory(available: Double, required: Double)
    case insufficientDiskSpace
    case downloadFailed(String)
    case sha256Mismatch(expected: String, actual: String)
    case modelTooSmall(Double)
    case noModelAvailable
    case modelStuckInLoop

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): return "Model not found: \(path)"
        case .engineInitFailed(let reason): return "Engine initialization failed: \(reason)"
        case .modelCorrupted(let path): return "Model file corrupted: \(path)"
        case .insufficientMemory(let avail, let req): return "Insufficient memory. Available: \(String(format: "%.1f", avail))GB, required: \(String(format: "%.1f", req))GB"
        case .insufficientDiskSpace: return "Not enough storage. Free up at least 1 GB."
        case .downloadFailed(let reason): return "Download failed: \(reason)"
        case .sha256Mismatch(let expected, let actual): return "File integrity check failed. Expected: \(expected), got: \(actual)"
        case .modelTooSmall(let size): return "Model file too small (\(String(format: "%.2f", size)) GB). Re-download recommended."
        case .noModelAvailable: return "No model available. Download a model in Settings."
        case .modelStuckInLoop: return "Model stuck in a loop. Try rephrasing your message or adjusting temperature in Settings."
        }
    }
}
