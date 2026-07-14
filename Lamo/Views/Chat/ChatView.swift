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
                    let tokenCount = viewModel.contextTracker?.messageUsages.first(where: { $0.id == message.id })?.tokenCount
                    MessageBubble(message: message, tokenCount: tokenCount, onRetry: {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ContextBarView(tracker: viewModel.contextTracker) {
                    showContextDetail = true
                }
            }
        }
        .sheet(isPresented: $showContextDetail) {
            ContextDetailView(tracker: viewModel.contextTracker)
        }
    }

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 80)

            VStack(spacing: 24) {
                // Animated logo
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 80, height: 80)

                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.black)
                }
                .shadow(color: .white.opacity(0.08), radius: 20, y: 8)

                VStack(spacing: 8) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                    Text("Running 100% on your device. No data leaves your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                // Suggestion chips
                VStack(spacing: 10) {
                    suggestionChip(icon: "lightbulb", text: "Explain quantum computing simply")
                    suggestionChip(icon: "text.badge.checkmark", text: "Write a professional email")
                    suggestionChip(icon: "swift", text: "Debug a Swift concurrency issue")
                }
                .padding(.top, 8)

                // Download CTA
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Download a Model", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func suggestionChip(icon: String, text: String) -> some View {
        Button {
            viewModel.inputText = text
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
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
            .background(Color.white.opacity(0.06))
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