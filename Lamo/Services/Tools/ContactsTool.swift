import Foundation
import LiteRTLM
import Contacts

// MARK: - Contacts Tool

struct ContactsTool: Tool {
    static let name = "contacts"
    static let description = "Search contacts by name, phone, or email."

    @ToolParam(description: "Search by name, phone, email, or organization.")
    var query: String

    @ToolParam(description: "Max contacts to return (1–20).")
    var maxResults: Int = 5

    func run() async throws -> Any {
        await ToolCallReporter.shared.reportCall(
            name: Self.name,
            params: "{\"query\": \"\(query)\", \"max_results\": \(maxResults)}"
        )

        let store = CNContactStore()

        // Check and request authorization
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else {
                let result: [String: Any] = [
                    "error": "Contacts access denied. Please enable in Settings > Privacy > Contacts."
                ]
                await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
                return result
            }
        case .restricted, .denied:
            let result: [String: Any] = [
                "error": "Contacts access denied. Please enable in Settings > Privacy > Contacts."
            ]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        case .authorized, .limited:
            break
        @unknown default:
            break
        }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let lowerQuery = query.lowercased()
        var matches: [[String: Any]] = []
        let cap = max(1, maxResults)

        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                if matches.count >= cap {
                    stop.pointee = true
                    return
                }

                let fullName = "\(contact.givenName) \(contact.familyName)"
                    .trimmingCharacters(in: .whitespaces)
                let org = contact.organizationName
                let phones = contact.phoneNumbers.map { $0.value.stringValue }
                let emails = contact.emailAddresses.map { ($0.value as String) }

                // Build searchable text from all fields
                let searchableText = [
                    fullName,
                    org,
                    phones.joined(separator: " "),
                    emails.joined(separator: " "),
                ].joined(separator: " ").lowercased()

                guard lowerQuery.isEmpty || searchableText.contains(lowerQuery) else { return }

                var entry: [String: Any] = ["name": fullName]
                if !org.isEmpty { entry["organization"] = org }
                if !phones.isEmpty { entry["phones"] = phones }
                if !emails.isEmpty { entry["emails"] = emails }
                matches.append(entry)
            }
        } catch {
            let result: [String: Any] = ["error": "Failed to read contacts: \(error.localizedDescription)"]
            await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
            return result
        }

        var result: [String: Any] = [
            "query": query,
            "count": matches.count,
            "contacts": matches,
        ]

        let limit = await AgenticLoopBudget.shared.consumeIteration()
        result = await TokenTruncator.truncateResult(result, maxTokens: limit) as? [String: Any] ?? result

        await ToolCallReporter.shared.reportResult(name: Self.name, result: result)
        return result
    }
}
