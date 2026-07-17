import SwiftUI

// MARK: - Tool Call Block (collapsible)

struct ToolCallBlock: View {
    let call: ToolCallRecord
    let isStreaming: Bool
    @State private var isExpanded = false

    private var accentColor: Color { Color(red: 0.35, green: 0.55, blue: 0.90) }
    private var isRunning: Bool { call.result == nil && isStreaming }
    private var borderColor: Color { isRunning ? accentColor.opacity(0.35) : Color(white: 0.5).opacity(0.12) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                accentColor.opacity(0.12).frame(height: 1).padding(.vertical, 6)
                if let result = call.result {
                    JSONTreeView(jsonString: result)
                } else {
                    Text(call.params)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(isRunning ? 0.2 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isRunning ? accentColor : Color(white: 0.5).opacity(0.45))
                    .symbolEffect(.bounce, value: isRunning)

                Text(displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isRunning ? Color(.secondaryLabel) : .secondary)

                if isRunning {
                    ProgressView().tint(accentColor).controlSize(.mini)
                    Text("running").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                if call.result != nil {
                    Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green.opacity(0.7))
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch call.name {
        case "web_search": return "globe"
        case "fetch_url": return "doc.text.magnifyingglass"
        case "get_current_time": return "clock"
        case "calculator": return "function"
        case "open_url": return "safari"
        case "wikipedia": return "book.closed"
        case "get_location": return "location.fill"
        case "device_info": return "iphone.gen3"
        case "weather": return "cloud.sun.fill"
        case "create_reminder": return "bell.badge.fill"
        case "update_memory": return "brain.fill"
        default: return "wrench.fill"
        }
    }

    private var displayName: String {
        call.name.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Universal JSON Tree View

/// Recursively renders any JSON as a clean, collapsible tree.
struct JSONTreeView: View {
    let jsonString: String

    var body: some View {
        if let root = parse(jsonString) {
            JSONNodeView(value: root, key: nil, depth: 0)
        } else {
            Text(jsonString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func parse(_ s: String) -> Any? {
        guard let d = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
}

// MARK: - JSON Node (recursive)

private struct JSONNodeView: View {
    let value: Any
    let key: String?
    let depth: Int

    var body: some View {
        switch value {
        case let dict as [String: Any]:
            ObjectNode(dict: dict, key: key, depth: depth)

        case let arr as [Any]:
            ArrayNode(array: arr, key: key, depth: depth)

        case let str as String:
            StringNode(text: str, key: key, depth: depth)

        case let nsnum as NSNumber:
            // Distinguish bool from number
            if CFGetTypeID(nsnum) == CFBooleanGetTypeID() {
                BoolNode(value: nsnum.boolValue, key: key)
            } else {
                NumberNode(number: nsnum, key: key)
            }

        case is NSNull:
            NullNode(key: key)

        default:
            Text("\(value)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Object Node

private struct ObjectNode: View {
    let dict: [String: Any]
    let key: String?
    let depth: Int
    @State private var expanded = true

    private let maxKeys = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    if let key { Text("\"\(key)\"").font(.system(.caption, design: .monospaced)).foregroundStyle(.blue.opacity(0.6)) }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    Text("{").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    Text("\(dict.count) keys").font(.caption2).foregroundStyle(.tertiary)
                    if !expanded { Text("}").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(dict.sorted(by: { $0.key < $1.key }).prefix(maxKeys)), id: \.key) { k, v in
                        JSONNodeView(value: v, key: k, depth: depth + 1)
                            .padding(.leading, 16)
                    }
                    if dict.count > maxKeys {
                        Text("… and \(dict.count - maxKeys) more keys")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.leading, 16)
                    }
                }
                Text("}").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Array Node

private struct ArrayNode: View {
    let array: [Any]
    let key: String?
    let depth: Int
    @State private var expanded = true

    private let maxItems = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    if let key {
                        Text("\"\(key)\"").font(.system(.caption, design: .monospaced)).foregroundStyle(.blue.opacity(0.6))
                        Text(":").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    Text("[\(array.count)]").font(.caption2).foregroundStyle(.tertiary)
                    if !expanded { Text("]").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(array.prefix(maxItems).enumerated()), id: \.offset) { i, item in
                        JSONNodeView(value: item, key: "[\(i)]", depth: depth + 1)
                            .padding(.leading, 16)
                    }
                    if array.count > maxItems {
                        Text("… and \(array.count - maxItems) more items")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.leading, 16)
                    }
                }
                Text("]").font(.system(.caption, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - String Node

private struct StringNode: View {
    let text: String
    let key: String?
    let depth: Int
    @State private var expanded = false

    private let shortLimit = 120
    private var isLong: Bool { text.count > shortLimit }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let key {
                Text("\"\(key)\":").font(.system(.caption, design: .monospaced)).foregroundStyle(.blue.opacity(0.6))
            }

            if isLong {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? text : String(text.prefix(shortLimit)) + "…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        if !expanded {
                            Text("more").font(.caption2).foregroundStyle(.blue.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - Number Node

private struct NumberNode: View {
    let number: NSNumber
    let key: String?

    private var formatted: String {
        let d = number.doubleValue
        if d == floor(d) && d.isFinite && abs(d) < 1e15 {
            return String(Int(d))
        }
        return String(format: "%.6g", d)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let key { Text("\"\(key)\":").font(.system(.caption, design: .monospaced)).foregroundStyle(.blue.opacity(0.6)) }
            Text(formatted)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.green.opacity(0.8))
        }
    }
}

// MARK: - Bool Node

private struct BoolNode: View {
    let value: Bool
    let key: String?

    var body: some View {
        HStack(spacing: 4) {
            if let key { Text("\"\(key)\":").font(.system(.caption, design: .monospaced)).foregroundStyle(.blue.opacity(0.6)) }
            Text(value ? "true" : "false")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(value ? .green.opacity(0.8) : .orange.opacity(0.8))
        }
    }
}

// MARK: - Null Node

private struct NullNode: View {
    let key: String?

    var body: some View {
        HStack(spacing: 4) {
            if let key { Text("\"\(key)\":").font(.system(.caption, design: .monospaced)).foregroundStyle(.blue.opacity(0.6)) }
            Text("null")
                .font(.system(.caption, design: .monospaced).italic())
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Container

struct ToolCallsView: View {
    let calls: [ToolCallRecord]
    let isStreaming: Bool
    var body: some View {
        ForEach(calls) { call in ToolCallBlock(call: call, isStreaming: isStreaming) }
    }
}
