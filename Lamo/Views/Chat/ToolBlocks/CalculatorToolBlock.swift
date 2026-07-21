import SwiftUI

// MARK: - Calculator

struct CalculatorResult: View {
    let d: [String: Any]
    private static let handled = Set(["expression", "error", "result"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let expr = d["expression"] as? String ?? ""
            if let error = d["error"] as? String {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.red.opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expr)
                            .font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                let r = d["result"] as? Double ?? 0
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "function")
                        .font(.title3).foregroundStyle(toolColor(name: "calculator").opacity(0.6))
                    Text(expr)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("=")
                        .font(.title3).foregroundStyle(.tertiary)
                    Text(formatNumber(r))
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
