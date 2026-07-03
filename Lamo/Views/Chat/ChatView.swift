import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    @State private var scrollPosition = ScrollPosition()
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
            .padding(.bottom, 8)
        }
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            hideKeyboard()
        }
        .onChange(of: viewModel.messages.count) {
            scrollToBottom()
        }
        .onChange(of: viewModel.messages.last?.content) {
            if isUserNearBottom {
                scrollToBottom()
            }
        }
        .safeAreaInset(edge: .bottom) {
            ChatInputBar(
                text: $viewModel.inputText,
                pendingImages: $viewModel.pendingImages,
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
                // Gradient logo
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [LamoTheme.Colors.accent, LamoTheme.Colors.accent.opacity(0.6)],
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
                    Text("Ask anything — I'm running 100% on your device.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
    }

    private func scrollToBottom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            scrollPosition.scrollTo(edge: .bottom)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
