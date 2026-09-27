import SwiftUI

// MARK: - Universal Field Grid

/// Renders every un-handled field of a tool result as a compact typed row.
/// Nested dictionaries and arrays expand inline, so no field a tool returns is
/// ever hidden — for any tool, current or future.
struct FieldGrid: View, Equatable {
    let dict: [String: Any]
    /// Keys already visualized by the surrounding card.
    var handled: Set<String> = []
    /// Standalone mode — shows a header with the tool name (fallback for tools
    /// that don't have a dedicated card yet).
    var title: String?
    /// Embedded mode draws a hairline above the rows; standalone mode draws a header instead.
    var showDivider: Bool = true

    // [String: Any] isn't Equatable — compare shape (keys/handling/flags) plus a
    // stringified snapshot for scalar payloads. Nested tool dicts are small.
    static func == (lhs: FieldGrid, rhs: FieldGrid) -> Bool {
        lhs.handled == rhs.handled
            && lhs.title == rhs.title
            && lhs.showDivider == rhs.showDivider
            && lhs.dict.keys.sorted() == rhs.dict.keys.sorted()
            && String(describing: lhs.dict) == String(describing: rhs.dict)
    }
    /// Отсортировано один раз в init — раньше filter+sorted выполнялись на каждый body.
    private let entries: [(key: String, value: Any)]

    init(dict: [String: Any], handled: Set<String> = [], title: String? = nil, showDivider: Bool = true) {
        self.dict = dict
        self.handled = handled
        self.title = title
        self.showDivider = showDivider
        self.entries = dict
            .filter { !handled.contains($0.key) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    HStack(spacing: 6) {
                        Image(systemName: toolIcon(name: title))
                            .font(.system(size: 11))
                            .foregroundStyle(toolColor(name: title).opacity(0.55))
                        Text(title.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                } else if showDivider {
                    ThinDivider()
                        .padding(.bottom, 4)
                }
                ForEach(entries, id: \.key) { key, value in
                    FieldRow(key: key, value: value)
                }
            }
        }
    }
}

// MARK: - Field Row

/// One key → value line. Dictionaries and arrays of objects expand on tap.
struct FieldRow: View {
    let key: String
    let value: Any
    var depth: Int = 0

    @State private var isExpanded = false

    private var keyLabel: String { key.replacingOccurrences(of: "_", with: " ") }

    /// Стабильный id для элементов массива: содержимое + индекс.
    fileprivate static func stableArrayID(for item: Any, fallback: Int) -> String {
        if let d = item as? [String: Any] {
            if let u = d["url"] as? String, !u.isEmpty { return u }
            if let t = d["title"] as? String, !t.isEmpty { return t }
            if let n = d["name"] as? String, !n.isEmpty { return n }
        }
        return "\(String(describing: type(of: item)))-\(fieldValue(item).prefix(32))-\(fallback)"
    }

    var body: some View {
        content
            .padding(.leading, CGFloat(depth) * 12)
    }

    @ViewBuilder
    private var content: some View {
        switch value {
        case let dict as [String: Any]:
            containerRow(badge: "{\(dict.count)}") {
                ForEach(dict.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    FieldRow(key: k, value: v, depth: depth + 1)
                }
            }
        case let arr as [Any]:
            if arr.allSatisfy({ !($0 is [String: Any]) && !($0 is [Any]) }) {
                scalarRow(arr)
            } else {
                containerRow(badge: "[\(arr.count)]") {
                    ForEach(Array(arr.enumerated()).map { (Self.stableArrayID(for: $0.element, fallback: $0.offset), $0.element, $0.offset) }, id: \.0) { _, item, i in
                        indexedRow(i, item)
                    }
                }
            }
        default:
            valueRow(display: fieldValue(value), color: fieldColor(value))
        }
    }

    // MARK: Leaf

    private func valueRow(display: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: fieldIcon(key))
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            Text(keyLabel)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(display)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 1)
    }

    private func scalarRow(_ arr: [Any]) -> some View {
        valueRow(display: arr.map { fieldValue($0) }.joined(separator: " · "), color: .secondary)
    }

    // MARK: Container

    private func containerRow<C: View>(badge: String, @ViewBuilder children: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: fieldIcon(key))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(keyLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(badge)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(LamoTheme.Colors.fillSubtle))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                children()
            }
        }
        .padding(.vertical, 1)
    }

    private func indexedRow(_ index: Int, _ item: Any) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(index + 1)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
                .padding(.top, 2)
            if let sub = item as? [String: Any] {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(sub.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                        FieldRow(key: k, value: v, depth: depth + 1)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: fieldIcon(""))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(fieldValue(item))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(fieldColor(item))
                }
            }
        }
    }
}

// MARK: - Error Card

/// Unified error presentation: red icon + message + hint, plus any other fields.
struct ErrorCard: View, Equatable {
    let d: [String: Any]

    static func == (lhs: ErrorCard, rhs: ErrorCard) -> Bool {
        NSDictionary(dictionary: lhs.d).isEqual(to: rhs.d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                ToolBadge(icon: "exclamationmark.triangle.fill", tint: LamoTheme.Colors.error, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d["error"] as? String ?? String(localized: "Tool failed"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    if let hint = d["hint"] as? String, !hint.isEmpty {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            FieldGrid(dict: d, handled: ["error", "hint"])
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(LamoTheme.Colors.error.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(LamoTheme.Colors.error.opacity(0.20), lineWidth: 0.5))
    }
}

// MARK: - Value Formatting

func fieldValue(_ value: Any) -> String {
    switch value {
    case let s as String:
        return s.count > 80 ? String(s.prefix(80)) + "…" : s
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
        return n.boolValue ? "true" : "false"
    case let n as NSNumber:
        return formatNumber(n.doubleValue)
    case is NSNull:
        return "—"
    case let arr as [Any]:
        return "[\(arr.count)]"
    case let d as [String: Any]:
        return "{\(d.count)}"
    default:
        return "\(value)"
    }
}

func fieldColor(_ value: Any) -> Color {
    switch value {
    case is String:  return .primary.opacity(0.85)
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID():
        return n.boolValue ? LamoTheme.Colors.success.opacity(0.8) : LamoTheme.Colors.warning.opacity(0.8)
    case is NSNumber: return LamoTheme.Colors.success.opacity(0.7)
    case is NSNull:   return .secondary.opacity(0.6)
    default:          return .secondary
    }
}

func fieldIcon(_ key: String) -> String {
    switch key {
    case let k where k.contains("temp"):      return "thermometer.medium"
    case let k where k.contains("humid"):      return "humidity.fill"
    case let k where k.contains("wind"):       return "wind"
    case let k where k.contains("url"):        return "link"
    case let k where k.contains("city") || k.contains("location"): return "mappin.and.ellipse"
    case let k where k.contains("time") || k.contains("date"):    return "clock"
    case let k where k.contains("battery"):    return "battery.75percent"
    case let k where k.contains("storage") || k.contains("disk"): return "internaldrive"
    case let k where k.contains("memory") || k.contains("ram"):   return "memorychip"
    case let k where k.contains("status"):     return "circlebadge"
    case let k where k.contains("error"):      return "xmark.circle"
    case let k where k.contains("name") || k.contains("title"):   return "textformat"
    case let k where k.contains("id"):         return "number"
    case let k where k.contains("count") || k.contains("number"): return "number.circle"
    case let k where k.contains("phone"):      return "phone.fill"
    case let k where k.contains("email"):      return "envelope.fill"
    default:                                    return "circle.fill"
    }
}
