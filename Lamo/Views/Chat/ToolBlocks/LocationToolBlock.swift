import SwiftUI

// MARK: - Location

struct LocationCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "location_name", "display", "city", "region", "country",
        "latitude", "longitude", "altitude_m", "horizontal_accuracy_m", "source"
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
        let source = d["source"] as? String

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ToolBadge(icon: "mappin.circle.fill", tint: toolColor(name: "get_location"), size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? "Unknown location" : name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        let subtitle = [region, country].compactMap { $0 }.joined(separator: ", ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let source, !source.isEmpty {
                            Chip(text: source.uppercased(), tint: source == "gps" ? .green : .blue,
                                 font: .system(size: 8, weight: .bold, design: .monospaced))
                        }
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
                if let acc = d["horizontal_accuracy_m"] as? Double, acc > 0 {
                    Label("±\(Int(acc))m", systemImage: "scope")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            FieldGrid(dict: d, handled: Self.handled)
        }
    }
}
