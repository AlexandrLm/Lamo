import SwiftUI
import UIKit

struct MessageBubble: View {
    let message: Message
    let onRetry: (() -> Void)?
    @State private var showCopyConfirmation = false
    @State private var showImageViewer = false
    @State private var selectedImageIndex = 0

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

            // Timestamp + actions
            HStack(spacing: 8) {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if message.role == .assistant {
                    copyButton
                }
            }
            .padding(.leading, message.role == .user ? 0 : 18)
            .padding(.trailing, message.role == .user ? 16 : 0)
        }
        .messageAppear()
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
                    .foregroundStyle(LamoTheme.Colors.bubbleTextUser)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(LamoTheme.Colors.accent)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16,
                            bottomLeadingRadius: message.hasImages ? 4 : 16,
                            bottomTrailingRadius: 16,
                            topTrailingRadius: 4,
                            style: .continuous
                        )
                    )
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

    private var copyButton: some View {
        Button { copyContent() } label: {
            if showCopyConfirmation {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy message")
        .sensoryFeedback(.impact(weight: .light), trigger: showCopyConfirmation)
    }

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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.accent)

                    if isStreaming && !isExpanded {
                        ProgressView()
                            .tint(LamoTheme.Colors.accent)
                            .controlSize(.small)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable thinking content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .overlay(Color(.separator).opacity(0.15))

                    ScrollView(.vertical, showsIndicators: false) {
                        MarkdownRenderer(
                            text: content,
                            textColor: .secondary,
                            isStreaming: isStreaming
                        )
                        .font(.footnote)
                    }
                    .frame(maxHeight: 300)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(.regular.tint(LamoTheme.Colors.accent.opacity(0.08)), in: .rect(cornerRadius: 10))
    }
}


