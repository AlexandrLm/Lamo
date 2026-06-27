import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CompactDivider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .scrollContentBackground(.hidden)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Message")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($isTextFieldFocused)

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color(.systemRed))
                            .clipShape(Circle())
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isTextFieldFocused = false
                        onSend()
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(canSend ? Color.white : Color(.tertiaryLabel))
                            .background(canSend ? Color.black : Color(.quaternarySystemFill), in: Circle())
                            .animation(.easeInOut(duration: 0.15), value: canSend)
                            .animation(.easeInOut(duration: 0.15), value: canSend)
                    }
                    .disabled(!canSend)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: LamoTheme.maxContentWidth)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
