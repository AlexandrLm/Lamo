import SwiftUI
import UIKit
import ImageIO

struct MessageBubble: View {
    let message: Message
    let tokenCount: Int?
    let onRetry: (() -> Void)?
    let onEdit: (() -> Void)?
    @State private var showCopyConfirmation = false
    @State private var showImageViewer = false
    @State private var selectedImageIndex = 0
    @State private var showActions = false
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
                            .foregroundStyle(.white.opacity(0.15))
                        Text("\(String(format: "%.1f", b.timeToFirstToken))s")
                    }
                    if let tokenCount {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.15))
                        Text("\(ContextTracker.formatTokens(tokenCount)) t")
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        actionButton(
                            icon: showCopyConfirmation ? "checkmark" : "doc.on.doc",
                            label: "Copy",
                            color: showCopyConfirmation ? .white : .white.opacity(0.3)
                        ) {
                            copyContent()
                        }

                        if let onRetry {
                            actionButton(icon: "arrow.clockwise", label: "Retry", color: .white.opacity(0.3)) {
                                onRetry()
                            }
                        }

                        actionButton(icon: "square.and.arrow.up", label: "Share", color: .white.opacity(0.3)) {
                            showShareSheet = true
                        }
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.3))
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
                            .foregroundStyle(.gray.opacity(0.5))
                    }

                    actionButton(
                        icon: showCopyConfirmation ? "checkmark" : "doc.on.doc",
                        label: "Copy",
                        color: showCopyConfirmation ? .white : .white.opacity(0.3)
                    ) {
                        copyContent()
                    }

                    if let onEdit {
                        actionButton(icon: "pencil", label: "Edit", color: .white.opacity(0.3)) {
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                    .foregroundStyle(.white.opacity(0.9))
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
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.attachedFileNames[index])
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if index < message.attachedFileSizes.count {
                            Text(message.attachedFileSizes[index])
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
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

            MarkdownRenderer(text: message.content, textColor: LamoTheme.Colors.textPrimary, isStreaming: message.isStreaming && message.content.isEmpty)
        }
        .textSelection(.enabled)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Warm amber accent — contrasts with the dark theme, immediately visible as "thinking" vs answer.
    private var accentColor: Color { Color(red: 0.94, green: 0.63, blue: 0.19) }

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
                        .foregroundStyle(accentColor)
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
                            .foregroundStyle(.secondary)
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
                            textColor: .secondary,
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
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
                    .contentShape(Rectangle())
                    .accessibilityLabel("Image attachment")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
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
                let img = Self.downsampledImage(at: path, maxPixelSize: 400)
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