import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Ask Lamo", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .animation(.easeOut(duration: 0.15), value: text.isEmpty)
                    .padding(.vertical, 10)
                // Send / Stop — comfortable tap target
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(.red, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else if canSend {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isTextFieldFocused = false
                        onSend()
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(LamoTheme.Colors.accent, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        }
        .frame(maxWidth: LamoTheme.maxContentWidth)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
