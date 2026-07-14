import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    @State private var scrollPosition = ScrollPosition()
    @State private var showContextDetail = false
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

                // Streaming indicator
                if viewModel.isStreaming && (viewModel.messages.last?.content.isEmpty ?? true) {
                    StreamingIndicator()
                        .id("streaming")
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
                .safeAreaInset(edge: .top) {
            ContextBarView(tracker: viewModel.contextTracker) {
                showContextDetail = true
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
        .overlay(alignment: .topTrailing) {
            if viewModel.isStreaming {
                Button(action: { viewModel.stopGeneration() }) {
                    EmptyView()
                }
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Stop generation")
                .hidden()
            }
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle(viewModel.messages.isEmpty ? "" : viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showContextDetail) {
            ContextDetailView(tracker: viewModel.contextTracker)
        }
    }

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)
            VStack(spacing: 20) {
                // Gradient logo
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.black)
                }

                VStack(spacing: 6) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                    Text("Ask anything — I'm running 100% on your device.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                // Empty state CTA: Download a Model button
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Download a Model", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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

// MARK: - Streaming Indicator (Three Dots)

struct StreamingIndicator: View {
    @State private var dotOffsets: [CGFloat] = [0, 0, 0]
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // Model avatar
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)

                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black)
            }

            // Bubble with dots
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .offset(y: dotOffsets[index])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 16,
                    topTrailingRadius: 16,
                    style: .continuous
                )
            )

            Spacer()
        }
        .padding(.horizontal, 16)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        animating = true
        for index in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.15)
            ) {
                dotOffsets[index] = -6
            }
        }
    }
}