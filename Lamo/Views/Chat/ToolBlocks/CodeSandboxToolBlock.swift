import SwiftUI

// MARK: - Code Sandbox

struct CodeSandboxCard: View {
    let d: [String: Any]
    private static let handled = Set(["output", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let isHTML = HTMLDetector.isHTML(d["output"] as? String ?? "")
            if let output = d["output"] as? String, !output.isEmpty {
                if isHTML {
                    HTMLCard(html: output, title: "HTML Output", maxHeight: 450)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal.fill")
                            .font(.caption).foregroundStyle(.green.opacity(0.7))
                        Text("Output")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(12)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                        .textSelection(.enabled)
                }
            }
            if let error = d["error"] as? String, !error.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red.opacity(0.7))
                    Text("Error")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .foregroundStyle(Color.orange)
                }
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(8)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                    .textSelection(.enabled)
            }
            if d["output"] == nil && d["error"] == nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green.opacity(0.6))
                    Text("Executed (no output)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
