import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import os

/// Checks whether Apple Foundation Models (SystemLanguageModel) is available
/// on this device. Guards against OS version and non-eligible hardware.
enum FoundationModelsAvailability {

    // MARK: - Cache (availability query hits the framework; coalesce bursts)

    private static var cachedAvailable: Bool?
    private static var cachedAt: Date?
    private static let cacheTTL: TimeInterval = 5

    // MARK: - Static strings (avoid re-creating localized strings per call)

    private static let requiresOS26 = String(localized: "Requires iOS 26 or macOS 26")
    private static let notEligible = String(localized: "This device does not support Apple Intelligence")
    private static let notEnabled = String(localized: "Apple Intelligence is turned off. Enable it in Settings → Apple Intelligence & Siri")
    private static let notReady = String(localized: "Apple Intelligence model is downloading or not yet ready")
    private static let unavailable = String(localized: "Apple Intelligence is unavailable")
    private static let noSDK = String(localized: "FoundationModels framework not available in this SDK")
    private static let unknown = String(localized: "Unknown")

    /// Whether Foundation Models is supported on this device.
    /// Requires iOS 26+ / macOS 26+ and an Apple Intelligence-eligible device
    /// (framework exists since iOS 26; iOS 27 only adds images, toolCallingMode,
    /// ContextOptions reasoning and the LanguageModelError taxonomy).
    static var isSupported: Bool {
        unavailabilityReason == nil
    }

    /// Whether Foundation Models is available AND ready for immediate use.
    /// Alias of `isSupported` (single source of truth — was a duplicate check).
    static var isReady: Bool { isSupported }

    /// Cached availability bit with 5s TTL (used by hot paths like menus).
    static var cachedIsSupported: Bool {
        if let cached = cachedAvailable, let at = cachedAt,
           Date().timeIntervalSince(at) < cacheTTL {
            return cached
        }
        let value = isSupported
        cachedAvailable = value
        cachedAt = Date()
        return value
    }

    static func invalidateCache() {
        cachedAvailable = nil
        cachedAt = nil
    }

    /// Human-readable reason why Foundation Models is unavailable, or nil if available.
    static var unavailabilityReason: String? {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return requiresOS26
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return notEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return notEnabled
        case .unavailable(.modelNotReady):
            return notReady
        case .unavailable:
            return unavailable
        }
#else
        return noSDK
#endif
    }

    /// Non-optional variant for UI fallbacks.
    static var unavailabilityReasonOrUnknown: String { unavailabilityReason ?? unknown }
}
