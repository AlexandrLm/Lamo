import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os

/// Checks whether Apple Foundation Models (SystemLanguageModel) is available
/// on this device. Guards against OS version and non-eligible hardware.
enum FoundationModelsAvailability {

    /// Whether Foundation Models is supported on this device.
    /// Requires iOS 27+ / macOS 27+ and an Apple Intelligence-eligible device.
    static var isSupported: Bool {
#if canImport(FoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else { return false }
        return SystemLanguageModel.default.availability == .available
#else
        return false
#endif
    }

    /// Human-readable reason why Foundation Models is unavailable, or nil if available.
    static var unavailabilityReason: String? {
#if canImport(FoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else {
            return String(localized: "Requires iOS 27 or macOS 27")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return String(localized: "This device does not support Apple Intelligence")
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence model is downloading or not yet ready")
        case .unavailable:
            return String(localized: "Apple Intelligence is unavailable")
        }
#else
        return String(localized: "FoundationModels framework not available in this SDK")
#endif
    }

    /// Whether Foundation Models is available AND ready for immediate use.
    static var isReady: Bool {
#if canImport(FoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else { return false }
        return SystemLanguageModel.default.availability == .available
#else
        return false
#endif
    }
}
