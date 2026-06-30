import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    private var provider: ProviderManager { ProviderManager.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Top: text field area
            TextField("Reply to Lamo", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Bottom: toolbar row
            HStack(spacing: 10) {
                // Plus button
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)

                // Model selector pill — shows real model name
                Button {} label: {
                    HStack(spacing: 6) {
                        Text(modelDisplayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if provider.isEngineReady {
                            Text("Ready")
                                .font(.system(size: 11))
                                .foregroundStyle(LamoTheme.Colors.accent)
                        } else {
                            Text("Loading")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Microphone button
                Button {} label: {
                    Image(systemName: "microphone")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)

                // Send / Stop button (white circle like the reference)
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Dimmed send when empty
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .frame(maxWidth: LamoTheme.maxContentWidth)
        .padding(.bottom, 6)
        .padding(.horizontal, 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    private var modelDisplayName: String {
        let name = provider.currentModelDisplayName
        return name.isEmpty ? "No Model" : name
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
