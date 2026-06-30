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
            // Input row
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

                // Send / Stop — native system buttons
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.red)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        isTextFieldFocused = false
                        onSend()
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(canSend ? LamoTheme.Colors.accent : Color(.quaternarySystemFill))
                            .glassEffect(.regular.interactive(), in: .circle)
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

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
