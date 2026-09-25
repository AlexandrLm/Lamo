import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    @State private var scrollPosition = ScrollPosition()
    @State private var showContextDetail = false
    @ObservedObject private var provider = ProviderManager.shared
    /// Кэш пунктов меню моделей: listModels() читает диск, нельзя вызывать в body.
    @State private var modelEntries: [ModelMenuEntry] = []
    /// Троттлинг догоняющего скролла во время стриминга.
    @State private var lastFollowScroll = Date.distantPast
    var onNewChat: (() -> Void)?

    init(
        conversation: Conversation,
        modelContext: ModelContext,
        onNewChat: (() -> Void)? = nil
    ) {
        _viewModel = State(wrappedValue: ChatViewModel(
            conversation: conversation,
            modelContext: modelContext
        ))
        self.onNewChat = onNewChat
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            chatScrollView

            if !isUserNearBottom && !viewModel.messages.isEmpty {
                scrollToBottomButton
            }
        }
        .background {
            ZStack {
                LamoTheme.Colors.background
                // Градиент — только на пустом экране. В переписке фон чистый,
                // чтобы ничего не мешало чтению.
                if viewModel.messages.isEmpty {
                    AmbientGradientView(
                        isReady: provider.isEngineReady,
                        hasError: provider.engineError != nil
                    )
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 1.2), value: viewModel.messages.isEmpty)
            .animation(.easeInOut(duration: 1.5), value: provider.isEngineReady)
            .animation(.easeInOut(duration: 1.5), value: provider.engineError)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(modelEntries, id: \.filename) { entry in
                        Button {
                            provider.switchModel(modelPath: entry.fullPath)
                        } label: {
                            HStack {
                                Text(entry.displayName)
                                if provider.litertLMModelPath == entry.fullPath {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if !provider.isEngineReady && provider.litertLMModelPath != nil {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                                .tint(LamoTheme.Colors.textLow)
                        }
                        Text(provider.currentModelDisplayName.isEmpty ? "No model" : provider.currentModelDisplayName)
                            .font(.system(size: 20, weight: .regular, design: .monospaced))
                            .foregroundStyle(provider.engineError != nil ? LamoTheme.Colors.error : LamoTheme.Colors.textMedium)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(provider.engineError != nil ? LamoTheme.Colors.error.opacity(0.6) : LamoTheme.Colors.textFaint)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(LamoTheme.Colors.error.opacity(provider.engineError != nil ? 0.15 : 0))
                    )
                    .overlay(
                        Capsule()
                            .stroke(LamoTheme.Colors.error.opacity(provider.engineError != nil ? 0.4 : 0), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.5), value: provider.engineError != nil)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ContextBarView(tracker: viewModel.contextTracker) {
                    showContextDetail = true
                }
            }
        }
        .sheet(isPresented: $showContextDetail) {
            ContextDetailView(tracker: viewModel.contextTracker)
        }
        .onAppear {
            refreshModelEntries()
        }
        .onChange(of: provider.litertLMModelPath) {
            refreshModelEntries()
        }
    }

    // MARK: - Model Menu (cached)

    /// Один пункт меню выбора модели. Кэшируется, чтобы не ходить в файловую
    /// систему и не пересчитывать отображаемые имена на каждый чих body
    /// (во время стриминга body пересчитывается на каждый токен).
    private struct ModelMenuEntry: Hashable {
        let filename: String
        let fullPath: String
        let displayName: String
    }

    private func refreshModelEntries() {
        modelEntries = ProviderManager.listModels().map { filename in
            let fullPath = ProviderManager.modelsDirectory.appendingPathComponent(filename).path
            return ModelMenuEntry(
                filename: filename,
                fullPath: fullPath,
                displayName: ProviderManager.displayName(forModelPath: filename)
            )
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
            lastFollowScroll = Date()
            scrollToBottom()
        }
        .onChange(of: viewModel.messages.last?.content) {
            // Догоняющий скролл с троттлингом: без него scrollTo дергается
            // на каждый токен стриминга, нагружая layout.
            guard isUserNearBottom else { return }
            let now = Date()
            guard now.timeIntervalSince(lastFollowScroll) > 0.12 else { return }
            lastFollowScroll = now
            scrollToBottom(animated: false)
        }
        .safeAreaInset(edge: .bottom) {
            ChatInputBar(
                text: $viewModel.inputText,
                pendingImages: $viewModel.pendingImages,
                pendingFiles: $viewModel.pendingFiles,
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
        // last?.id один раз вместо обращения на каждый пузырь при ре-рендере.
        let lastID = viewModel.messages.last?.id
        return LazyVStack(spacing: 16) {
            if viewModel.messages.isEmpty {
                emptyChatView
                    .id("empty")
            }

            ForEach(viewModel.messages) { message in
                // Dictionary lookup — O(1); the old first(where:) scan ran per
                // bubble on every render pass.
                let tokenCount = viewModel.messageTokenCounts[message.id]
                MessageBubble(
                    message: message,
                    tokenCount: tokenCount,
                    // Info-bar retry only makes sense on the conversation's last message:
                    // it regenerates that response without touching earlier history.
                    onRetry: message.id == lastID ? {
                        viewModel.retryLastMessage()
                    } : nil,
                    // Error banner retry anchors to the failed message and regenerates
                    // from it onward (delete-onward, like edit).
                    onRetryError: {
                        viewModel.retryMessage(message)
                    },
                    onEdit: message.role == .user ? {
                        viewModel.editMessage(message)
                    } : nil
                )
                .id(message.id)
            }

            // Compression notification
            if let compression = provider.lastCompression {
                CompressionCard(oldCount: compression.oldCount, summary: compression.summary) {
                    provider.lastCompression = nil
                }
                .id("compression")
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            if viewModel.isStreaming && (viewModel.messages.last?.content.isEmpty ?? true) {
                StreamingIndicator()
                    .id("streaming")
            }
        }
        // Единая ширина контента с инпут-баром: на iPad и в альбомной
        // ориентации строки не разъезжаются на всю ширину экрана.
        .frame(maxWidth: LamoTheme.maxContentWidth)
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
                .foregroundStyle(LamoTheme.Colors.textMedium)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.interactive(), in: .circle)
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
                Text("Lamo")
                    .font(.system(size: 40, weight: .light, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(LamoTheme.Colors.textGhost)

                VStack(spacing: 6) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                    Text("Running 100% on your device")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if provider.litertLMModelPath == nil && provider.selectedProviderType == .litertLM {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Download a Model", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(LamoTheme.Colors.textMedium)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 8)
                }
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

// MARK: - Streaming Indicator (Pulsing Cursor)

struct StreamingIndicator: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LamoTheme.Colors.textHigh)
                .frame(width: 2.5, height: 16)
                .opacity(opacity)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                opacity = 0.8
            }
        }
    }
}

// MARK: - Ambient Gradient (empty state only)

/// Мягкое «северное сияние» за пустым экраном: верхняя вуаль + два медленно
/// дрейфующих размытых пятна. Плавная анимация через repeatForever —
/// без ступенчатых скачков TimelineView. В переписке не используется.
private struct AmbientGradientView: View {
    let isReady: Bool
    let hasError: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false

    private var isDark: Bool { colorScheme == .dark }

    /// Основной и вторичный оттенки в зависимости от состояния движка.
    private var tintPrimary: Color {
        if hasError { return .red }
        if !isReady { return .orange }
        return LamoTheme.Colors.accent
    }

    private var tintSecondary: Color {
        if hasError { return .orange }
        if !isReady { return .yellow }
        return Color(red: 0.35, green: 0.55, blue: 0.90)
    }

    private var orbOpacity: Double { isDark ? 0.22 : 0.15 }

    var body: some View {
        ZStack {
            // Верхняя вуаль — задаёт общий тон, сходит на нет к середине.
            LinearGradient(
                stops: [
                    .init(color: tintPrimary.opacity(isDark ? 0.16 : 0.10), location: 0),
                    .init(color: tintSecondary.opacity(isDark ? 0.08 : 0.05), location: 0.25),
                    .init(color: .clear, location: 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Пятно 1 — тил, сверху слева.
            Circle()
                .fill(tintPrimary.opacity(orbOpacity))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: drift ? 40 : -40, y: drift ? 20 : -30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(hasError || !isReady ? (drift ? 1.0 : 0.75) : 1.0)

            // Пятно 2 — синее, сверху справа, движется в противофазе.
            Circle()
                .fill(tintSecondary.opacity(orbOpacity * 0.8))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: drift ? -30 : 35, y: drift ? -20 : 25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}