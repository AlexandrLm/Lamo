import SwiftUI
import SwiftData

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isUserNearBottom = true
    @Environment(\.modelContext) private var modelContext
    @State private var scrollPosition = ScrollPosition()
    @State private var showContextDetail = false
    @ObservedObject private var provider = ProviderManager.shared
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
                AmbientGradientView(
                    intensity: viewModel.messages.isEmpty ? 1.0 : 0.12,
                    isReady: provider.isEngineReady,
                    hasError: provider.engineError != nil
                )
                    .ignoresSafeArea(edges: .top)
            }
            .animation(.easeInOut(duration: 1.2), value: viewModel.messages.isEmpty)
            .animation(.easeInOut(duration: 1.5), value: provider.isEngineReady)
            .animation(.easeInOut(duration: 1.5), value: provider.engineError)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(ProviderManager.listModels(), id: \.self) { filename in
                        let fullPath = ProviderManager.modelsDirectory.appendingPathComponent(filename).path
                        let displayName = ProviderManager.displayName(forModelPath: filename)
                        Button {
                            provider.switchModel(modelPath: fullPath)
                        } label: {
                            HStack {
                                Text(displayName)
                                if provider.litertLMModelPath == fullPath {
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
                                .tint(.white.opacity(0.4))
                        }
                        Text(provider.currentModelDisplayName.isEmpty ? "No model" : provider.currentModelDisplayName)
                            .font(.system(size: 20, weight: .regular, design: .monospaced))
                            .foregroundStyle(provider.engineError != nil ? .red : .white.opacity(0.7))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(provider.engineError != nil ? .red.opacity(0.6) : .white.opacity(0.3))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.red.opacity(provider.engineError != nil ? 0.15 : 0))
                    )
                    .overlay(
                        Capsule()
                            .stroke(.red.opacity(provider.engineError != nil ? 0.4 : 0), lineWidth: 1)
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
        LazyVStack(spacing: 16) {
            if viewModel.messages.isEmpty {
                emptyChatView
                    .id("empty")
            }

            ForEach(viewModel.messages) { message in
                let tokenCount = viewModel.contextTracker?.messageUsages.first(where: { $0.id == message.id })?.tokenCount
                MessageBubble(message: message, tokenCount: tokenCount, onRetry: {
                    viewModel.retryLastMessage()
                }, onEdit: message.role == .user ? {
                    viewModel.editMessage(message)
                } : nil)
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
                    .foregroundStyle(.white.opacity(0.15))

                VStack(spacing: 6) {
                    Text("How can I help you today?")
                        .font(.title2.weight(.semibold))
                    Text("Running 100% on your device")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if ProviderManager.shared.litertLMModelPath == nil {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Download a Model", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
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

    private var modelDotColor: Color {
        if provider.isEngineReady { return LamoTheme.Colors.accent }
        if provider.engineError != nil { return .orange }
        if provider.litertLMModelPath != nil { return .white.opacity(0.4) }
        return .white.opacity(0.2)
    }

}

// MARK: - Streaming Indicator (Pulsing Cursor)

struct StreamingIndicator: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white)
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

// MARK: - Ambient Gradient

/// A living, slowly shifting gradient backdrop.
/// Uses `TimelineView` for seamless continuous animation — no autoreverse jerk.
private struct AmbientGradientView: View {
    /// 1.0 = full vibrant (empty state), 0.0 = invisible
    let intensity: CGFloat
    let isReady: Bool
    let hasError: Bool

    /// Base hue shifts depending on engine state:
    ///   Ready   → teal  (0.58)
    ///   Loading → amber (0.12)
    ///   Error   → red   (0.02)
    private var baseHue: Double {
        if hasError { return 0.02 }
        if !isReady { return 0.12 }
        return 0.58
    }

    private func color(
        at t: Double,
        hueShift: Double,
        satBase: Double,
        briBase: Double,
        pulse: Double
    ) -> Color {
        let h = baseHue + hueShift
        let s = satBase + 0.05 * cos(t * 0.25)
        let b = briBase * intensity * pulse
        return Color(hue: h, saturation: s, brightness: b)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse: Double = {
                if hasError { return 1.0 + 0.25 * abs(sin(t * 2.0)) }
                if !isReady { return 1.0 + 0.12 * abs(sin(t * 1.2)) }
                return 1.0
            }()
            let s0: Double = hasError ? 0.70 : 0.40
            let s1: Double = hasError ? 0.55 : 0.30
            let s2: Double = hasError ? 0.40 : 0.18
            let b0: Double = hasError ? 0.32 : 0.38
            let b1: Double = hasError ? 0.22 : 0.25
            let b2: Double = hasError ? 0.14 : 0.16

            LinearGradient(
                stops: [
                    .init(color: color(at: t, hueShift: 0.04 * sin(t * 0.3), satBase: s0, briBase: b0 + 0.05 * sin(t * 0.25), pulse: pulse), location: 0),
                    .init(color: color(at: t, hueShift: 0.06 * cos(t * 0.35), satBase: s1, briBase: b1 + 0.04 * cos(t * 0.22), pulse: pulse), location: 0.20),
                    .init(color: color(at: t, hueShift: 0.07 * sin(t * 0.4), satBase: s2, briBase: b2 + 0.03 * sin(t * 0.35), pulse: pulse), location: 0.40),
                    .init(color: .clear, location: 0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}