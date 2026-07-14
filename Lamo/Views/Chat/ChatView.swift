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
        ZStack(alignment: .bottomTrailing) {
            chatScrollView

            // "Scroll to bottom" floating button
            if !isUserNearBottom && !viewModel.messages.isEmpty {
                scrollToBottomButton
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

    // MARK: - Chat Scroll View

    private var chatScrollView: some View {
        ScrollView {
            chatMessageList
        }
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            hideKeyboard()
        }
        .onScrollGeometryChange(for: Bool.self) { (geo: ScrollGeometry) -> Bool in
            let bottomEdge = geo.contentOffset.y + geo.containerSize.height
            return bottomEdge >= geo.contentSize.height - 150
        } action: { (_: Bool, nearBottom: Bool) in
            isUserNearBottom = nearBottom
        }
        .onChange(of: viewModel.messages.count) {
            isUserNearBottom = true
            scrollToBottom()
        }
        .onChange(of: viewModel.messages.last?.content) {
            if isUserNearBottom {
                scrollToBottom(animated: false)
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
    }

    private var chatMessageList: some View {
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

            if viewModel.isStreaming && (viewModel.messages.last?.content.isEmpty ?? true) {
                StreamingIndicator()
                    .id("streaming")
            }
        }
        .padding(.vertical, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Scroll to Bottom Button

    private var scrollToBottomButton: some View {
        Button {
            isUserNearBottom = true
            scrollToBottom()
        } label: {
            Image(systemName: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 80)
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 100)

            VStack(spacing: 20) {
                LogoAnimationView(size: 100)
                    .shadow(color: .white.opacity(0.04), radius: 30, y: 8)

                VStack(spacing: 6) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                    Text("Running 100% on your device")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Download a Model", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func scrollToBottom(animated: Bool = true) {
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        } else {
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
            // Dots only — no avatar
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .offset(y: dotOffsets[index])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
                dotOffsets[index] = -5
            }
        }
    }
}