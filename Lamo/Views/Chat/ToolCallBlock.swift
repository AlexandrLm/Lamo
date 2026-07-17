import SwiftUI

/// Collapsible block showing a tool call and its result — same visual style as ThinkingView.
struct ToolCallBlock: View {
    let call: ToolCallRecord
    let isStreaming: Bool
    @State private var isExpanded = false

    private var accentColor: Color { Color(red: 0.35, green: 0.55, blue: 0.90) }

    private var iconName: String {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.bounce, value: call.result == nil && isStreaming)

                    Text(displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(call.result == nil ? textColor : .secondary)

                    if call.result == nil && isStreaming {
                        HStack(spacing: 4) {
                            ProgressView()
                                .tint(accentColor)
                                .controlSize(.mini)
                            Text("running")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if call.result != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.7))
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable detail
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    accentColor.opacity(0.12)
                        .frame(height: 1)
                        .padding(.bottom, 6)

                    if let result = call.result {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxHeight: 200)
                    } else {
                        Text(call.params)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(call.result == nil && isStreaming ? 0.2 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var iconColor: Color {
        if call.result == nil && isStreaming { return accentColor }
        return Color(white: 0.5).opacity(0.45)
    }

    private var borderColor: Color {
        if call.result == nil && isStreaming { return accentColor.opacity(0.35) }
        return Color(white: 0.5).opacity(0.12)
    }

    private var textColor: Color {
        isStreaming ? Color(.secondaryLabel) : Color(.tertiaryLabel)
    }
}

/// Renders all tool call blocks for a message.
struct ToolCallsView: View {
    let calls: [ToolCallRecord]
    let isStreaming: Bool

    var body: some View {
        ForEach(calls) { call in
            ToolCallBlock(call: call, isStreaming: isStreaming)
        }
    }
}
