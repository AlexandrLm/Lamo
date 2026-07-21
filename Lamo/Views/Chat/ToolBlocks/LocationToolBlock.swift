import SwiftUI

// MARK: - Location

struct LocationCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "location_name", "display", "city", "region", "country",
        "latitude", "longitude", "altitude_m", "horizontal_accuracy_m", "source", "timezone"
    ])

    var body: some View {
        let name = d["location_name"] as? String
            ?? d["display"] as? String
            ?? d["city"] as? String
            ?? ""
        let lat = d["latitude"] as? Double ?? 0
        let lon = d["longitude"] as? Double ?? 0
        let region = d["region"] as? String
        let country = d["country"] as? String

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title3).foregroundStyle(.red.opacity(0.8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? "Unknown location" : name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    let subtitle = [region, country].compactMap { $0 }.joined(separator: ", ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 16) {
                Label(
                    "\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))",
                    systemImage: "smallcircle.filled.circle"
                ).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                if let alt = d["altitude_m"] as? Double {
                    Label("\(Int(alt))m", systemImage: "mountain.2")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
