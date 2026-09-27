import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os

// MARK: - Constants

private enum Constants {
    static let barCornerRadius: CGFloat = 22
    static let buttonSize: CGFloat = 32
    static let maxPhotoSelection = 5
}

// MARK: - ChatInputBar

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var pendingImages: [PendingImage]
    @Binding var pendingFiles: [PendingFile]
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isTextFieldFocused: Bool
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var sendCount = 0
    @State private var showAttachPanel = false
    @State private var pickerTask: Task<Void, Never>?
    /// Снапшот плейсхолдера — обновляется только по релевантным изменениям провайдера,
    /// а не на каждый objectWillChange (иначе TextField ре-рендерился постоянно).
    @State private var placeholderText: String = "Reply to Lamo"

    /// Текст/вложения есть — без engineReady (его добавит тулбар со своим наблюдением).
    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !pendingImages.isEmpty
            || !pendingFiles.isEmpty
    }

    private static func makePlaceholder() -> String {
        let pm = ProviderManager.shared
        if pm.selectedProviderType == .litertLM && pm.litertLMModelPath == nil {
            return "Download a model to start"
        }
        if !pm.isEngineReady { return "Loading model…" }
        return "Reply to Lamo"
    }

    var body: some View {
        VStack(spacing: 0) {
            if showAttachPanel { attachPanel }
            if !pendingImages.isEmpty { pendingImagesRow }
            if !pendingFiles.isEmpty { pendingFilesRow }

            InputFieldView(text: $text, placeholder: placeholderText, isFocused: $isTextFieldFocused)

            ThinDivider()
                .padding(.horizontal, 12)

            InputToolbarView(
                isStreaming: isStreaming,
                hasContent: hasContent,
                attachCount: pendingImages.count + pendingFiles.count,
                showAttachPanel: $showAttachPanel,
                sendCount: $sendCount,
                onSend: {
                    isTextFieldFocused = false
                    showAttachPanel = false
                    onSend()
                },
                onStop: onStop,
                onCamera: {
                    if CameraView.isAvailable {
                        showCamera = true
                    } else {
                        showPhotoPicker = true
                    }
                },
                onPhotos: { showPhotoPicker = true },
                onFiles: { showFileImporter = true }
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Constants.barCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.barCornerRadius, style: .continuous)
                .stroke(LamoTheme.Colors.accent.opacity(isTextFieldFocused ? 0.5 : 0), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.2), value: isTextFieldFocused)
        .frame(maxWidth: LamoTheme.maxContentWidth)
        .padding(.bottom, 6)
        .padding(.horizontal, 5)
        .onDrop(of: [.image, .fileURL], delegate: ChatDropDelegate(pendingImages: $pendingImages, pendingFiles: $pendingFiles))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
        .animation(.easeOut(duration: 0.15), value: hasContent)
        .onAppear { placeholderText = isStreaming ? "Generating…" : Self.makePlaceholder() }
        .onChange(of: isStreaming) { _, streaming in
            placeholderText = streaming ? "Generating…" : Self.makePlaceholder()
        }
        .onReceive(ProviderManager.shared.$isEngineReady) { _ in
            if !isStreaming { placeholderText = Self.makePlaceholder() }
        }
        .onChange(of: isTextFieldFocused) { _, focused in
            // Фокус в поле ввода вежливо закрывает панель вложений.
            if focused && showAttachPanel {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    showAttachPanel = false
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(onCapture: { captured in
                // Ресайз в фоне — полный кадр камеры (12МП) вешал main на ~200мс.
                Task.detached(priority: .userInitiated) {
                    let resized = captured.resizedForModel(maxDimension: ChatDropDelegate.maxImageDimension)
                    await MainActor.run { pendingImages.append(PendingImage(image: resized)) }
                }
            })
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems,
                      maxSelectionCount: Constants.maxPhotoSelection, matching: .images)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.data],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls { pendingFiles.append(PendingFile(url: url)) }
            case .failure(let error):
                LamoLogger.ui.error("File import failed: \(error)")
            }
        }
        .onChange(of: photoPickerItems) {
            guard !photoPickerItems.isEmpty else { return }
            pickerTask?.cancel()
            let items = photoPickerItems
            pickerTask = Task {
                for item in items {
                    guard !Task.isCancelled else { break }
                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            // Декод + ресайз в фоне, append на main.
                            let resized = await Task.detached(priority: .userInitiated) {
                                image.resizedForModel(maxDimension: ChatDropDelegate.maxImageDimension)
                            }.value
                            guard !Task.isCancelled else { break }
                            await MainActor.run { pendingImages.append(PendingImage(image: resized)) }
                        }
                    } catch {
                        LamoLogger.ui.error("Photo picker load failed: \(error)")
                    }
                }
                await MainActor.run { photoPickerItems = [] }
            }
        }
        .onDisappear { pickerTask?.cancel() }
    }

    // MARK: - Attach panel

    private var attachPanel: some View {
        HStack(spacing: 8) {
            attachOption(icon: "camera", title: "Camera") {
                // На симуляторе камеры нет — ведём в галерею вместо падения.
                if CameraView.isAvailable {
                    showCamera = true
                } else {
                    showPhotoPicker = true
                }
            }
            attachOption(icon: "photo.on.rectangle", title: "Photos") {
                showPhotoPicker = true
            }
            attachOption(icon: "doc", title: "Files") {
                showFileImporter = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func attachOption(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                showAttachPanel = false
            }
            // Даём панели схлопнуться до появления модалки пикера.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(LamoTheme.Colors.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .accessibilityLabel(title)
    }

    // MARK: - Pending Images Preview

    private var pendingImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { item in
                    PendingImageThumb(
                        image: item.image,
                        onRemove: {
                            withAnimation(.spring(response: 0.2)) {
                                pendingImages.removeAll { $0.id == item.id }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Pending Files Preview

    private var pendingFilesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingFiles) { file in
                    PendingFileThumb(file: file) {
                        withAnimation(.spring(response: 0.2)) {
                            pendingFiles.removeAll { $0.id == file.id }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, pendingImages.isEmpty ? 10 : 4)
            .padding(.bottom, 4)
        }
    }
}

// MARK: - Input Field (без наблюдения за провайдером)

/// Только TextField — не подписан на ProviderManager, поэтому ре-рендерится
/// лишь при изменении текста/плейсхолдера/фокуса, а не на каждый чих движка.
private struct InputFieldView: View {
    @Binding var text: String
    let placeholder: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(1...8)
            .font(.body)
            .textFieldStyle(.plain)
            .focused(isFocused)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }
}

// MARK: - Toolbar (единственный наблюдатель провайдера в баре)

/// Плюс / thinking / send — весь ProviderManager-обсервинг живёт здесь,
/// TextField выше его изменения не затрагивают.
private struct InputToolbarView: View {
    let isStreaming: Bool
    let hasContent: Bool
    let attachCount: Int
    @Binding var showAttachPanel: Bool
    @Binding var sendCount: Int
    let onSend: () -> Void
    let onStop: () -> Void
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    @ObservedObject private var provider = ProviderManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var onAccent: Color { colorScheme == .dark ? .black : .white }
    private var thinkingSupported: Bool { provider.selectedProviderType == .litertLM }
    private var canSend: Bool { provider.isEngineReady && hasContent }

    var body: some View {
        HStack(spacing: 10) {
            plusButton
            thinkingButton
            Spacer()
            sendButton
        }
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    private var plusButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                showAttachPanel.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: showAttachPanel ? "xmark" : "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                if attachCount > 0 {
                    Text("\(attachCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(onAccent)
                        .frame(width: 16, height: 16)
                        .background(LamoTheme.Colors.accent, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .sensoryFeedback(.impact(flexibility: .soft), trigger: showAttachPanel)
        .accessibilityLabel(showAttachPanel ? "Close attachments" : "Attachments")
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: showAttachPanel)
    }

    private var thinkingButton: some View {
        Button {
            provider.thinkingMode.toggle()
        } label: {
            Image(systemName: provider.thinkingMode ? "brain.head.profile.fill" : "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(provider.thinkingMode
                    ? LamoTheme.Colors.accent
                    : thinkingSupported ? LamoTheme.Colors.textFaint : LamoTheme.Colors.textGhost)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(provider.thinkingMode
                            ? LamoTheme.Colors.accent.opacity(0.2)
                            : LamoTheme.Colors.fillSubtle)
                )
                .overlay(
                    Circle()
                        .stroke(provider.thinkingMode
                            ? LamoTheme.Colors.accent.opacity(0.6)
                            : LamoTheme.Colors.fillStrong,
                            lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(!thinkingSupported)
        .opacity(thinkingSupported ? 1.0 : 0.4)
        .accessibilityLabel("Thinking mode")
    }

    @ViewBuilder
    private var sendButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(onAccent)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .background(LamoTheme.Colors.accent, in: Circle())
                    .shadow(color: LamoTheme.Colors.accent.opacity(colorScheme == .dark ? 0.4 : 0.25), radius: 6, y: 1)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Stop generation")
        } else if canSend {
            Button(action: {
                sendCount += 1
                onSend()
            }) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(onAccent)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .background(LamoTheme.Colors.accent, in: Circle())
                    .shadow(color: LamoTheme.Colors.accent.opacity(colorScheme == .dark ? 0.4 : 0.25), radius: 6, y: 1)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: sendCount)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Send message")
        } else {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(LamoTheme.Colors.fillStrong, in: Circle())
        }
    }
}
