import Foundation
import Darwin

/// Guards model-controlled URL fetches against SSRF and local-network access.
///
/// A language model can be steered (by page content, a crafted message, or a
/// compromised search result) into "fetching" an address that only the device
/// itself can reach: the router admin panel, a LAN service, or a cloud metadata
/// endpoint. Everything here is about keeping that class of request out.
nonisolated enum SecureURLPolicy {
    /// Model instructions only ever need to fetch public web pages.
    static let maxBodyBytes = 2 * 1024 * 1024
    static let maxRedirects = 5
    static let requestTimeout: TimeInterval = 15

    /// Hosts that are never useful for page fetching, blocked before any DNS work.
    static let blockedHostSuffixes: Set<String> = [
        "localhost", "local", "internal", "home.arpa", "localdomain"
    ]

    enum Rejection: LocalizedError {
        case notSecure
        case malformed
        case credentialsInURL
        case blockedHost(String)
        case privateAddress

        var errorDescription: String? {
            switch self {
            case .notSecure:
                return "Only https:// URLs can be fetched."
            case .malformed:
                return "The URL is malformed."
            case .credentialsInURL:
                return "URLs with embedded credentials are not allowed."
            case .blockedHost(let host):
                return "Local and internal hosts are blocked: \(host)."
            case .privateAddress:
                return "The address resolves to a private or local network."
            }
        }
    }

    /// Validate scheme, credentials and literal host of a URL.
    static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased() else { throw Rejection.malformed }
        guard scheme == "https" else { throw Rejection.notSecure }
        guard url.user == nil, url.password == nil else { throw Rejection.credentialsInURL }
        guard let host = url.host?.lowercased(), !host.isEmpty else { throw Rejection.malformed }

        for suffix in blockedHostSuffixes where host == suffix || host.hasSuffix("." + suffix) {
            throw Rejection.blockedHost(host)
        }
        // IPv6 literals: `URL.host` already strips the brackets, so a colon is
        // the reliable marker.
        if host.contains(":") {
            if isPrivateIPv6(host) { throw Rejection.privateAddress }
        } else if isPrivateIPv4(host) {
            throw Rejection.privateAddress
        }
    }

    /// Session used for fetching: no cookies, no credential reuse, and a bounded
    /// redirect chain so a redirect cannot walk into the local network.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout * 2
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Re-validate every hop: `URLSession` follows redirects on its own, so the
    /// final URL must be checked after the response as well.
    static func validateResolvedAddresses(of url: URL) async throws {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return }
        // A literal IP needs no resolution.
        if isPrivateIPv4(host) || host.contains(":") { return }
        try Task.checkCancellation()
        try validateDNSResolution(of: host)
    }

    /// Resolve and reject any address inside a private/loopback range, so a
    /// public-looking hostname that points at 192.168.x.x cannot be used to
    /// reach the local network.
    private static func validateDNSResolution(of host: String) throws {
        var hints = addrinfo()
        hints.ai_family = AF_INET          // IPv4 is the realistic SSRF vector here
        hints.ai_flags = AI_ADDRCONFIG

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let head = result else { return }
        defer { freeaddrinfo(head) }

        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let info = cursor {
            if let sockaddr = info.pointee.ai_addr {
                var address = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let text = String(cString: buffer)
                    if isPrivateIPv4(text) { throw Rejection.privateAddress }
                }
            }
            cursor = info.pointee.ai_next
        }
    }

    // MARK: - Address classification

    private static func isPrivateIPv4(_ host: String) -> Bool {
        var octets: [Int] = []
        for part in host.split(separator: ".") {
            guard part.count <= 3, let value = Int(part) else { return false }
            octets.append(value)
        }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        let a = octets[0], b = octets[1], c = octets[2]
        switch a {
        case 0, 10, 127: return true                       // reserved, private, loopback
        case 169 where b == 254: return true               // link-local (incl. 169.254.169.254)
        case 172 where (16...31).contains(b): return true  // RFC1918
        case 192 where b == 168: return true               // RFC1918
        case 100 where (64...127).contains(b): return true  // CGNAT
        case 192 where b == 0 && c == 2: return true        // documentation
        case 198 where (18...19).contains(b): return true   // benchmarking
        default: return false
        }
    }

    private static func isPrivateIPv6(_ literal: String) -> Bool {
        let value = literal.lowercased()
        if value == "::" || value == "::1" { return true }               // unspecified / loopback
        if value.hasPrefix("fe80") || value.hasPrefix("fc") || value.hasPrefix("fd") { return true }
        // IPv4-mapped (::ffff:10.0.0.1) must be checked by the embedded address.
        if let mapped = value.split(separator: ":").last,
           isPrivateIPv4(String(mapped)) {
            return true
        }
        return false
    }
}
