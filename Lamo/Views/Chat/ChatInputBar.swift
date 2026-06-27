import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: LamoTheme.Spacing.sm) {
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .scrollContentBackground(.hidden)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 26))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Message...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($isTextFieldFocused)

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular, in: .circle)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isTextFieldFocused = false
                        onSend()
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(canSend ? .white : Color(.tertiaryLabel))
                            .frame(width: 38, height: 38)
                            .background(
                                canSend
                                    ? AnyShapeStyle(LamoTheme.Colors.accent)
                                    : AnyShapeStyle(Color(.quaternarySystemFill)),
                                in: .circle
                            )
                            .animation(.easeInOut(duration: 0.15), value: canSend)
                    }
                    .disabled(!canSend)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: LamoTheme.maxContentWidth)
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, 10)
            .padding(.bottom, 6)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
