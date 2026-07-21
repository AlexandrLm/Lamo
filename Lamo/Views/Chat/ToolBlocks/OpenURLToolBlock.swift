import SwiftUI

// MARK: - Open URL

struct OpenURLResult: View {
    let d: [String: Any]
    private static let handled = Set(["opened", "url", "error"])

    var body: some View {
        let opened = d["opened"] as? Bool ?? false
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: opened ? "safari" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(opened ? .blue : .red.opacity(0.7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(opened ? "Opened in browser" : "Could not open")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(opened ? .primary : Color.orange)
                    Text(shortURL(d["url"] as? String ?? ""))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.6))
                }
            }
            if let err = d["error"] as? String, !opened {
                Text(err).font(.caption2).foregroundStyle(.red.opacity(0.7))
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
