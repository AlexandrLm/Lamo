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
        _viewModel = State(wrappedValue: ChatViewModel(conversation: conversation, modelContext: modelContext))
        self.onNewChat = onNewChat
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: LamoTheme.Spacing.lg) {
                            if viewModel.messages.isEmpty {
                                emptyChatView
                                    .id("empty")
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message, onRetry: {
                                    Task {
                                        await viewModel.retryLastMessage()
                                    }
                                })
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, LamoTheme.Spacing.lg)
                        .padding(.vertical, LamoTheme.Spacing.xl)
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, LamoTheme.Spacing.lg)
                        .padding(.bottom, LamoTheme.Spacing.lg)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }

            ChatInputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { Task { await viewModel.send() } },
                onStop: { viewModel.stopGeneration() }
            )
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNewChat?()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.tint)
                }
                .sensoryFeedback(.selection, trigger: viewModel.messages.count)
            }
        }
    }

    // MARK: - Empty State

    private var emptyChatView: some View {
        VStack(spacing: LamoTheme.Spacing.xxl) {
            Spacer(minLength: 40)

            VStack(spacing: LamoTheme.Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tint)
                    .frame(width: 72, height: 72)
                    .glassEffect(.regular, in: .circle)

                VStack(spacing: LamoTheme.Spacing.sm) {
                    Text("How can I help?")
                        .font(.title2.bold())

                    Text("Powered by offline intelligence")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
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
