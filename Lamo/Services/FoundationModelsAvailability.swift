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

    private static let requiresOS27 = String(localized: "Requires iOS 27 or macOS 27")
    private static let notEligible = String(localized: "This device does not support Apple Intelligence")
    private static let notReady = String(localized: "Apple Intelligence model is downloading or not yet ready")
    private static let unavailable = String(localized: "Apple Intelligence is unavailable")
    private static let noSDK = String(localized: "FoundationModels framework not available in this SDK")
    private static let unknown = String(localized: "Unknown")

    /// Whether Foundation Models is supported on this device.
    /// Requires iOS 27+ / macOS 27+ and an Apple Intelligence-eligible device.
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
        guard #available(iOS 27.0, macOS 27.0, *) else {
            return requiresOS27
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return notEligible
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
