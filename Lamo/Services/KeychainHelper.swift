import Foundation
import Security
import os

/// Small Keychain wrapper for storing secrets (API keys, tokens).
nonisolated enum KeychainHelper {
    private static let service = LamoLogger.subsystem + ".keys"
    private static let logger = Logger(subsystem: LamoLogger.subsystem, category: "keychain")

    enum KeychainError: LocalizedError, Sendable {
        case unexpectedData
        case operationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedData:
                return "The secure value could not be decoded."
            case .operationFailed(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
                return "Keychain operation failed: \(message) (\(status))."
            }
        }
    }

    /// Update in place when the item exists, add only when it does not.
    /// The previous delete+add sequence dropped access control on every save and
    /// left a window where the key did not exist at all.
    @discardableResult
    nonisolated static func save(key: String, value: String) -> Bool {
        do {
            try saveChecked(key: key, value: value)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func saveChecked(key: String, value: String) throws {
        let identity = identityQuery(key: key)
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]

        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            logger.error("Keychain update failed for key '\(key)': OSStatus \(updateStatus)")
            throw KeychainError.operationFailed(updateStatus)
        }

        var insertion = identity
        insertion.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Another writer inserted the same account between update and add.
            let retry = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
            guard retry == errSecSuccess else { throw KeychainError.operationFailed(retry) }
            return
        }
        guard addStatus == errSecSuccess else {
            logger.error("Keychain save failed for key '\(key)': OSStatus \(addStatus)")
            throw KeychainError.operationFailed(addStatus)
        }
    }

    nonisolated static func load(key: String) -> String? {
        try? loadChecked(key: key)
    }

    /// Returns nil only when the key is genuinely absent; decoding and OSStatus
    /// failures are surfaced instead of being reported as "no key".
    nonisolated static func loadChecked(key: String) throws -> String? {
        var query = identityQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.operationFailed(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return value
    }

    @discardableResult
    nonisolated static func delete(key: String) -> Bool {
        do {
            try deleteChecked(key: key)
            return true
        } catch {
            return false
        }
    }

    nonisolated static func deleteChecked(key: String) throws {
        let status = SecItemDelete(identityQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for key '\(key)': OSStatus \(status)")
            throw KeychainError.operationFailed(status)
        }
    }

    /// Test hook: true when the process can actually use the Keychain.
    /// Unsigned simulator/CI test hosts get `errSecMissingEntitlement` (-34018)
    /// or `errSecNotAvailable` (-25291) and must skip Keychain assertions.
    nonisolated static func isKeychainAvailable() -> Bool {
        let probe = "lamo_keychain_probe"
        do {
            try saveChecked(key: probe, value: "1")
            defer { try? deleteChecked(key: probe) }
            return try loadChecked(key: probe) == "1"
        } catch {
            return false
        }
    }

    private static func identityQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
