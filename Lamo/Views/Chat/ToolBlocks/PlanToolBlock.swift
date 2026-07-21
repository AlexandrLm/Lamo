import SwiftUI

// MARK: - Plan

struct PlanCard: View {
    let d: [String: Any]
    private static let handled = Set(["plan_created", "goal", "total_steps", "steps", "error"])

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = d["error"] as? String {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.red.opacity(0.7))
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let goal = d["goal"] as? String ?? ""
                let total = d["total_steps"] as? Int ?? 0
                let steps = d["steps"] as? [[String: Any]] ?? []

                // Goal header
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .font(.title3).foregroundStyle(toolColor(name: "create_plan").opacity(0.7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(total) step\(total == 1 ? "" : "s")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Steps with connector line
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        // Step number + connector
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(toolColor(name: "create_plan").opacity(0.2))
                                    .frame(width: 20, height: 20)
                                Text("\(i + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(toolColor(name: "create_plan"))
                            }
                            if i < steps.count - 1 {
                                Rectangle()
                                    .fill(toolColor(name: "create_plan").opacity(0.15))
                                    .frame(width: 1.5)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: toolIcon(name: step["tool"] as? String ?? ""))
                                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                                Text(step["tool"] as? String ?? "")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.blue.opacity(0.5))
                            }
                            Text(step["description"] as? String ?? "")
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, i < steps.count - 1 ? 8 : 0)
                    }
                }
            }
            ExtraFields(dict: d, handled: Self.handled)
        }
    }
}
