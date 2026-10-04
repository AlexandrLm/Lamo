import SwiftUI
import UIKit
import ImageIO

struct MessageBubble: View {
    let message: Message
    let tokenCount: Int?
    /// Info-bar retry — regenerates the last assistant response only (no delete-onward).
    /// Pass nil unless this message is the conversation's last message.
    let onRetry: (() -> Void)?
    /// Error-banner retry — regenerates from this failed message onward (delete-onward,
    /// mirrors edit semantics). Only invoked on messages with errorDescription.
    let onRetryError: (() -> Void)?
    let onEdit: (() -> Void)?
    @State private var showCopyConfirmation = false
    @State private var showImageViewer = false
    @State private var selectedImageIndex = 0
    @State private var showShareSheet = false
    @State private var copyConfirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
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
                HStack(spacing: 6) {
                    if let b = message.benchmark {
                        Text("\(String(format: "%.0f", b.decodeTokensPerSec)) tok/s")
                        Text("·")
                            .foregroundStyle(LamoTheme.Colors.textGhost)
                        Text("\(String(format: "%.1f", b.timeToFirstToken))s")
                    }
                    if let tokenCount {
                        Text("·")
                            .foregroundStyle(LamoTheme.Colors.textGhost)
                        Text("\(ContextTracker.formatTokens(tokenCount)) t")
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        actionButton(
                            icon: showCopyConfirmation ? "checkmark" : "doc.on.doc",
                            label: String(localized: "Copy"),
                            color: showCopyConfirmation ? LamoTheme.Colors.textHigh : LamoTheme.Colors.textFaint
                        ) {
                            copyContent()
                        }

                        if let onRetry {
                            actionButton(icon: "arrow.clockwise", label: String(localized: "Retry"), color: LamoTheme.Colors.textFaint) {
                                onRetry()
                            }
                        }

                        actionButton(icon: "square.and.arrow.up", label: String(localized: "Share"), color: LamoTheme.Colors.textFaint) {
                            showShareSheet = true
                        }
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // User timestamp + actions
            if message.role == .user && !message.content.isEmpty {
                HStack(spacing: 8) {
                    Spacer()

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let tokenCount {
                        Text("· \(ContextTracker.formatTokens(tokenCount))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(LamoTheme.Colors.textLow)
                    }

                    actionButton(
                        icon: showCopyConfirmation ? "checkmark" : "doc.on.doc",
                        label: String(localized: "Copy"),
                        color: showCopyConfirmation ? LamoTheme.Colors.textHigh : LamoTheme.Colors.textFaint
                    ) {
                        copyContent()
                    }

                    if let onEdit {
                        actionButton(icon: "pencil", label: String(localized: "Edit"), color: LamoTheme.Colors.textFaint) {
                            onEdit()
                        }
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

    // MARK: - Action Button

    private func actionButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        RowActionButton(icon: icon, label: label, color: color, size: 26, iconSize: 11, action: action)
    }

    // MARK: - User Content

    private var userContent: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if message.hasImages {
                userImagesView
            }

            if message.hasAttachedFiles {
                userFilesView
            }

            if !message.content.isEmpty {
                Text(message.content)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - User Files

    private var userFilesView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(message.attachedFileNames.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Image(systemName: fileIcon(for: index))
                        .font(.system(size: 14))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.attachedFileNames[index])
                            .font(.subheadline)
                            .foregroundStyle(LamoTheme.Colors.textHigh)
                            .lineLimit(1)

                        if index < message.attachedFileSizes.count {
                            Text(message.attachedFileSizes[index])
                                .font(.caption2)
                                .foregroundStyle(LamoTheme.Colors.textLow)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(LamoTheme.Colors.fillMedium)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 260)
            }
        }
    }

    private func fileIcon(for index: Int) -> String {
        guard index < message.attachedFileNames.count else { return "doc" }
        let name = message.attachedFileNames[index]
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "xlsx", "xls", "csv": return "tablecells"
        case "pptx", "ppt": return "rectangle.on.rectangle"
        case "swift", "py", "js", "ts", "java", "kt", "go", "rs", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "mp4", "mov": return "film"
        default: return "doc"
        }
    }

    // MARK: - User Images

    private var userImagesView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.imagePaths.indices, id: \.self) { index in
                    let path = message.imagePaths[index]
                    AsyncThumbnailView(path: path)
                        .onTapGesture {
                            selectedImageIndex = index
                            showImageViewer = true
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .fullScreenCover(isPresented: $showImageViewer) {
            let uiImages = message.imagePaths.map { path -> UIImage in
                // Load at full resolution for the viewer (cache or disk)
                if let cached = ImageCache.shared.image(forKey: path) { return cached }
                return UIImage(contentsOfFile: path) ?? UIImage()
            }
            ImageViewer(images: uiImages, startIndex: selectedImageIndex)
                .ignoresSafeArea()
        }
    }

    // MARK: - Assistant Content

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.thinkingContent.isEmpty {
                ThinkingView(content: message.thinkingContent, isStreaming: message.isStreaming)
            }

            if !message.toolCalls.isEmpty {
                ToolCallsView(calls: message.toolCalls, isStreaming: message.isStreaming)
            }

            if HTMLDetector.isHTML(message.content) {
                HTMLCard(html: message.content, title: nil, maxHeight: 500)
            } else {
                MarkdownRenderer(text: message.content, textColor: LamoTheme.Colors.textPrimary, isStreaming: message.isStreaming && message.content.isEmpty)
            }

            if let error = message.errorDescription, !message.isStreaming {
                errorBanner(error: error)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Red error banner for failed generations. Partial content (if any) stays visible
    /// above; the banner carries the error text and a retry action.
    private func errorBanner(error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(LamoTheme.Colors.error)

            VStack(alignment: .leading, spacing: 2) {
                Text("Generation failed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            if let onRetryError {
                Button(action: onRetryError) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(LamoTheme.Colors.error.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry generation")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LamoTheme.Colors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(LamoTheme.Colors.error.opacity(0.28), lineWidth: 1)
        )
    }
    // MARK: - Actions

    private func copyContent() {
        let content = message.content
        #if os(iOS)
        UIPasteboard.general.string = content
        #endif
        // Cancel any previous reset task to avoid flicker on rapid re-copy
        copyConfirmationTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showCopyConfirmation = true
        }
        copyConfirmationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
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

    /// Warm amber accent — bright in dark, deeper in light for contrast on white.
    private var accentColor: Color {
        LamoTheme.Colors.thinkingAmber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to expand/collapse
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.breathe, value: isStreaming)

                    if isStreaming && !isExpanded {
                        HStack(spacing: 6) {
                            Text("Thinking")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .tint(accentColor)
                                .controlSize(.mini)
                        }
                        Spacer()
                    } else {
                        Text("Thinking")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(textColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable thinking content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    accentColor.opacity(0.15)
                        .frame(height: 1)
                        .padding(.bottom, 6)

                    ScrollView(.vertical, showsIndicators: false) {
                        MarkdownRenderer(
                            text: content,
                            textColor: isStreaming ? Color(.secondaryLabel) : Color(.tertiaryLabel),
                            isStreaming: isStreaming
                        )
                        .font(.footnote)
                        .padding(.top, 2)
                    }
                    .frame(maxHeight: 300)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LamoTheme.Colors.fillSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.6), value: isStreaming)
    }

    // MARK: - Dimmed appearance after streaming

    private var iconColor: Color {
        isStreaming ? accentColor : LamoTheme.Colors.textLow
    }

    private var borderColor: Color {
        isStreaming ? accentColor.opacity(0.35) : LamoTheme.Colors.fillStrong.opacity(0.8)
    }

    private var textColor: Color {
        isStreaming ? Color(.secondaryLabel) : Color(.tertiaryLabel)
    }
}

// MARK: - Async Thumbnail Loader

/// Loads image thumbnails off the main thread to prevent scroll stuttering.
/// Checks ImageCache first (O(1)), falls back to async disk load.
private struct AsyncThumbnailView: View {
    let path: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(LamoTheme.Colors.fillStrong, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                    .accessibilityLabel("Image attachment")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LamoTheme.Colors.fillSubtle)
                    .frame(width: 80, height: 80)
                    .overlay {
                        ProgressView()
                            .controlSize(.mini)
                    }
            }
        }
        .task(id: path) {
            // Check cache first (instant, thread-safe NSCache)
            if let cached = ImageCache.shared.image(forKey: path) {
                self.image = cached
                return
            }
            // Load from disk on background thread
            if let loaded = await loadInBackground(path) {
                ImageCache.shared.setImage(loaded, forKey: path)
                self.image = loaded
            }
        }
    }

    private func loadInBackground(_ path: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // 600px covers 200pt @3x — crisp thumbnails on ProMotion iPhones.
                let img = Self.downsampledImage(at: path, maxPixelSize: 600)
                continuation.resume(returning: img)
            }
        }
    }

    /// Downsample an image file using ImageIO — loads only what's needed for the target size.
    private static func downsampledImage(at path: String, maxPixelSize: CGFloat) -> UIImage? {
        let url = URL(fileURLWithPath: path)
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
