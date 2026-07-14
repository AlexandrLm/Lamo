import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: Message
    let tokenCount: Int?
    let onRetry: (() -> Void)?
    @State private var showCopyConfirmation = false
    @State private var showImageViewer = false
    @State private var selectedImageIndex = 0
    @State private var showActions = false
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            // Content
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    userContent
                }
                .padding(.horizontal, 16)
            } else {
                assistantContent
            }

            // Info bar (assistant only — always visible)
            if message.role == .assistant && !message.isStreaming && !message.content.isEmpty {
                HStack(spacing: 4) {
                    // Left: benchmark stats
                    HStack(spacing: 4) {
                        if let b = message.benchmark {
                            statPill(icon: "bolt.fill", text: "\(String(format: "%.0f", b.decodeTokensPerSec)) tok/s")
                            Text("·")
                                .foregroundStyle(.white.opacity(0.15))
                            statPill(icon: "timer", text: "\(String(format: "%.1f", b.timeToFirstToken))s")
                        } else {
                            statPill(icon: "bolt.fill", text: "— tok/s")
                            Text("·")
                                .foregroundStyle(.white.opacity(0.15))
                            statPill(icon: "timer", text: "— s")
                        }
                        if let tokenCount {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.15))
                            statPill(icon: "textformat.size", text: "\(ContextTracker.formatTokens(tokenCount)) t")
                        }
                    }
                    .font(.caption2.monospacedDigit())

                    Spacer()

                    // Right: model + actions
                    Text(modelName)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.35))

                    actionButton(
                        icon: showCopyConfirmation ? "checkmark" : "doc.on.doc",
                        label: "Copy",
                        color: showCopyConfirmation ? Color.white : Color(.tertiaryLabel)
                    ) {
                        copyContent()
                    }

                    if let onRetry {
                        actionButton(icon: "arrow.clockwise", label: "Retry", color: Color(.tertiaryLabel)) {
                            onRetry()
                        }
                    }

                    actionButton(icon: "square.and.arrow.up", label: "Share", color: Color(.tertiaryLabel)) {
                        showShareSheet = true
                    }
                }
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // User timestamp + token count
            if message.role == .user {
                HStack {
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let tokenCount {
                        Text("· ~\(ContextTracker.formatTokens(tokenCount))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                }
                .padding(.trailing, 16)
            }
        }
        .messageAppear()
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [message.content])
        }
    }

    // MARK: - Model Badge

    private var modelBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 8))
            Text(modelName)
                .font(.system(.caption2, design: .rounded).weight(.medium))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
    }

    private var modelName: String {
        let name = ProviderManager.shared.currentModelDisplayName
        return name.isEmpty ? "AI" : name
    }

    // MARK: - Action Button

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Stat Pill

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(text)
        }
    }

    // MARK: - User Content

    private var userContent: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Attached images
            if message.hasImages {
                userImagesView
            }

            // Text content (only if non-empty)
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 18,
                            bottomLeadingRadius: message.hasImages ? 4 : 18,
                            bottomTrailingRadius: 18,
                            topTrailingRadius: 4,
                            style: .continuous
                        )
                    )
                    .shadow(color: .white.opacity(0.06), radius: 8, y: 2)
            }
        }
    }

    // MARK: - User Images

    private var userImagesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.imagePaths.indices, id: \.self) { index in
                    let path = message.imagePaths[index]
                    let uiImage: UIImage? = {
                        if let cached = ImageCache.shared.image(forKey: path) {
                            return cached
                        }
                        if let loaded = UIImage(contentsOfFile: path) {
                            ImageCache.shared.setImage(loaded, forKey: path)
                            return loaded
                        }
                        return nil
                    }()
                    if let uiImage {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 200, maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                            .accessibilityLabel("Image attachment")
                            .onTapGesture {
                                selectedImageIndex = index
                                showImageViewer = true
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .fullScreenCover(isPresented: $showImageViewer) {
            let uiImages = message.imagePaths.compactMap { path -> UIImage? in
                if let cached = ImageCache.shared.image(forKey: path) { return cached }
                if let loaded = UIImage(contentsOfFile: path) {
                    ImageCache.shared.setImage(loaded, forKey: path)
                    return loaded
                }
                return nil
            }
            ImageViewer(images: uiImages, startIndex: selectedImageIndex)
                .ignoresSafeArea()
        }
    }

    // MARK: - Assistant Content

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thinking content (collapsible)
            if !message.thinkingContent.isEmpty {
                ThinkingView(content: message.thinkingContent, isStreaming: message.isStreaming)
            }

            // Main content
            MarkdownRenderer(text: message.content, textColor: LamoTheme.Colors.textPrimary, isStreaming: message.isStreaming && message.content.isEmpty)
        }
        .textSelection(.enabled)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func copyContent() {
        let content = message.content
        #if os(iOS)
        UIPasteboard.general.string = content
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopyConfirmation = false }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Appear Modifier

struct MessageAppearModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func messageAppear() -> some View {
        modifier(MessageAppearModifier())
    }
}

// MARK: - Thinking View

struct ThinkingView: View {
    let content: String
    let isStreaming: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to expand/collapse
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.8))

                    if isStreaming && !isExpanded {
                        HStack(spacing: 4) {
                            ProgressView()
                                .tint(Color.white.opacity(0.6))
                                .controlSize(.mini)
                            Text("Thinking…")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Thinking")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable thinking content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .overlay(Color(.separator).opacity(0.1))

                    ScrollView(.vertical, showsIndicators: false) {
                        MarkdownRenderer(
                            text: content,
                            textColor: .secondary,
                            isStreaming: isStreaming
                        )
                        .font(.footnote)
                    }
                    .frame(maxHeight: 300)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(.regular.tint(Color.white.opacity(0.06)), in: .rect(cornerRadius: 12))
    }
}