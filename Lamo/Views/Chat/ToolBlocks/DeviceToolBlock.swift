import SwiftUI

// MARK: - Device Info

struct DeviceCard: View {
    let d: [String: Any]
    private static let handled = Set([
        "device_name", "device_model", "device_model_identifier",
        "system_name", "system_version", "battery_level", "battery_state",
        "physical_memory_gb", "free_storage", "total_storage",
        "processor_count", "uptime_seconds", "is_low_power_mode"
    ])

    var body: some View {
        let name = d["device_name"] as? String ?? ""
        let model = d["device_model"] as? String ?? ""
        let os = "\(d["system_name"] as? String ?? "") \(d["system_version"] as? String ?? "")"

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(model) · \(os)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "iphone.gen3")
                    .font(.title2).foregroundStyle(.white.opacity(0.2))
            }
            BatteryBar(level: d["battery_level"] as? Int ?? 0)
            StorageBar(free: d["free_storage"] as? String ?? "", total: d["total_storage"] as? String ?? "")
            HStack(spacing: 16) {
                Label(
                    "\(d["physical_memory_gb"] as? String ?? "?") GB RAM",
                    systemImage: "memorychip"
                ).font(.caption2).foregroundStyle(.tertiary)
                Label(
                    "Uptime \(fmtUptime(d["uptime_seconds"] as? Int ?? 0))",
                    systemImage: "clock.arrow.circlepath"
                ).font(.caption2).foregroundStyle(.tertiary)
                if (d["is_low_power_mode"] as? Bool) == true {
                    Label("LPM", systemImage: "battery.25percent")
                        .font(.caption2).foregroundStyle(.yellow)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}

struct BatteryBar: View {
    let level: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: level <= 10 ? "battery.0percent"
                : level <= 25 ? "battery.25percent"
                : "battery.75percent")
                .font(.caption2)
                .foregroundStyle(level <= 10 ? .red : level <= 20 ? .orange : .green)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level <= 10 ? Color.red : level <= 20 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * CGFloat(level) / 100, height: 5)
                }
            }.frame(height: 5)
            Text("\(level)%").font(.caption2).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

struct StorageBar: View {
    let free: String; let total: String
    var body: some View {
        let fb = parseBytes(free); let tb = parseBytes(total)
        if tb > 0 {
            let frac = CGFloat(tb - fb) / CGFloat(tb)
            HStack(spacing: 8) {
                Image(systemName: "internaldrive")
                    .font(.caption2).foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(frac > 0.9 ? Color.orange : Color.white.opacity(0.25))
                            .frame(width: geo.size.width * frac, height: 5)
                    }
                }.frame(height: 5)
                Text("\(free) free / \(total)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
