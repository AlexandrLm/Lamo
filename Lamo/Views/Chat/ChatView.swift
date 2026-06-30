import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    var onNewChat: (() -> Void)?

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        onNewChat: (() -> Void)? = nil
    ) {
        let provider = ProviderManager.shared.currentProvider
        _viewModel = State(wrappedValue: ChatViewModel(
            conversation: conversation,
            modelContext: modelContext,
            provider: provider
        ))
        self.onNewChat = onNewChat
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if viewModel.messages.isEmpty {
                                emptyChatView
                                    .id("empty")
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onRetry: {
                                    viewModel.retryLastMessage()
                                })
                                .id(message.id)
                            }
                        }
                        .padding(.vertical, 20)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .global).maxY
                            )
                        })
                    }
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                        let screenHeight = UIScreen.main.bounds.height
                        isUserNearBottom = maxY < screenHeight + 150
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        hideKeyboard()
                    }
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.messages.last?.content) {
                        if isUserNearBottom {
                            scrollToBottom(proxy: proxy)
                        }
                    }

                    if !isUserNearBottom, !viewModel.messages.isEmpty {
                        Button {
                            scrollToBottom(proxy: proxy)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }

            ChatInputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { viewModel.send() },
                onStop: { viewModel.stopGeneration() }
            )
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle(viewModel.messages.isEmpty ? "" : viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)

            VStack(spacing: 20) {
                // App icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    LamoTheme.Colors.accent,
                                    LamoTheme.Colors.accent.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: LamoTheme.Colors.accent.opacity(0.3), radius: 12, y: 4)

                VStack(spacing: 6) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)

                    Text("Ask anything — I'm running 100% on your device.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            // Suggestion prompts
            VStack(spacing: 10) {
                suggestionRow(
                    icon: "lightbulb.fill",
                    title: "Explain",
                    subtitle: "quantum computing in simple terms",
                    prompt: "Explain quantum computing in simple terms"
                )
                suggestionRow(
                    icon: "code",
                    title: "Write",
                    subtitle: "a Swift function to sort an array",
                    prompt: "Write a Swift function to sort an array of integers using quicksort"
                )
                suggestionRow(
                    icon: "envelope.fill",
                    title: "Draft",
                    subtitle: "a professional email to a client",
                    prompt: "Draft a professional email to a client explaining a project delay"
                )
                suggestionRow(
                    icon: "list.bullet",
                    title: "Create",
                    subtitle: "a meal plan for the week",
                    prompt: "Create a healthy meal plan for the week with breakfast, lunch, and dinner"
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)

            Spacer()
        }
    }

    private func suggestionRow(icon: String, title: String, subtitle: String, prompt: String) -> some View {
        Button {
            viewModel.inputText = prompt
            viewModel.send()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Scroll Offset

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
