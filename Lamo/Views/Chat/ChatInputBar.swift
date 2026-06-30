import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    @State private var isTextEmpty = true

    var body: some View {
        VStack(spacing: 0) {
            // Model indicator
            modelIndicator

            HStack(alignment: .bottom, spacing: 10) {
                // Plus button (future: photo attach)
                Button {
                    // TODO: photo attach
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)

                // Text field with liquid glass
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .scrollContentBackground(.hidden)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                    .overlay(alignment: .topLeading) {
                        if isTextEmpty {
                            Text("Message")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !isTextEmpty {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    text = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.tertiary)
                                    .padding(.trailing, 10)
                                    .padding(.top, 10)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .focused($isTextFieldFocused)
                    .onChange(of: text) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isTextEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                    }

                // Send / Stop button
                if isStreaming {
                    Button(action: onStop) {
                        ZStack {
                            Circle()
                                .fill(Color(.systemRed))
                                .frame(width: 34, height: 34)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white)
                                .frame(width: 12, height: 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isTextFieldFocused = false
                        onSend()
                    }) {
                        ZStack {
                            Circle()
                                .fill(canSend ? LamoTheme.Colors.accent : Color(.quaternarySystemFill))
                                .frame(width: 34, height: 34)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(canSend ? .white : Color(.tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: LamoTheme.maxContentWidth)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .padding(.bottom, 6)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
        .animation(.easeOut(duration: 0.15), value: isTextEmpty)
    }

    // MARK: - Model Indicator

    private var modelIndicator: some View {
        let provider = ProviderManager.shared
        let modelName = provider.currentModelDisplayName

        return Group {
            if !modelName.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(provider.isEngineReady ? LamoTheme.Colors.accent : .orange)
                        .frame(width: 6, height: 6)
                    Text(modelName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
            }
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
