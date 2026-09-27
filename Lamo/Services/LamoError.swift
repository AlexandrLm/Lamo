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
    /// Engine was requested before ProviderManager finished initialization.
    /// Inference must never lazily create its own engine (slow I/O on the
    /// streaming path + duplicate config); callers must await initialization first.
    case engineNotReady
    case foundationModelsUnavailable(String)
    case foundationModelsError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): return String(localized: "Model not found: \(path)")
        case .engineInitFailed(let reason): return String(localized: "Engine initialization failed: \(reason)")
        case .modelCorrupted(let path): return String(localized: "Model file corrupted: \(path)")
        case .insufficientMemory(let avail, let req):
            return String(localized: "Insufficient memory. Available: \(avail, format: .number.precision(.fractionLength(1)))GB, required: \(req, format: .number.precision(.fractionLength(1)))GB")
        case .insufficientDiskSpace: return String(localized: "Not enough storage. Free up at least 1 GB.")
        case .modelTooSmall(let size): return String(localized: "Model file too small (\(size, format: .number.precision(.fractionLength(2))) GB). Re-download recommended.")
        case .noModelAvailable: return String(localized: "No model available. Download a model in Settings.")
        case .modelStuckInLoop: return String(localized: "Model stuck in a loop. Try rephrasing your message or adjusting temperature in Settings.")
        case .engineNotReady: return String(localized: "The model engine is not ready yet. Open the app and wait for it to finish loading, then retry.")
        case .foundationModelsUnavailable(let reason): return String(localized: "Apple Intelligence unavailable: \(reason)")
        case .foundationModelsError(let message): return String(localized: "Apple Intelligence error: \(message)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotFound: return String(localized: "Download the model again in Settings > Models.")
        case .engineInitFailed: return String(localized: "Restart the app and try again. If it persists, re-download the model.")
        case .modelCorrupted: return String(localized: "Delete the model file and re-download it.")
        case .insufficientMemory: return String(localized: "Close other apps or choose a smaller model.")
        case .insufficientDiskSpace: return String(localized: "Free up at least 1 GB of storage, then retry.")
        case .modelTooSmall: return String(localized: "Delete the partial file and re-download the model.")
        case .noModelAvailable: return String(localized: "Open Settings > Models and download a model.")
        case .modelStuckInLoop: return String(localized: "Rephrase your message or lower the temperature in Settings.")
        case .engineNotReady: return String(localized: "Wait for the model to finish loading, then try again.")
        case .foundationModelsUnavailable: return String(localized: "Check that Apple Intelligence is enabled and the device supports it.")
        case .foundationModelsError: return String(localized: "Try again. If the error persists, restart the app.")
        }
    }

    /// Stable numeric code for logging/telemetry.
    var code: Int {
        switch self {
        case .modelNotFound: return 1001
        case .engineInitFailed: return 1002
        case .modelCorrupted: return 1003
        case .insufficientMemory: return 1004
        case .insufficientDiskSpace: return 1005
        case .modelTooSmall: return 1006
        case .noModelAvailable: return 1007
        case .modelStuckInLoop: return 1008
        case .engineNotReady: return 1011
        case .foundationModelsUnavailable: return 1009
        case .foundationModelsError: return 1010
        }
    }
}
