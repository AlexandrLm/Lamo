import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os
import Combine

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var pendingImages: [UIImage]
    @Binding var pendingFiles: [PendingFile]
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    @State private var showModelPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var sendTrigger = false
    @State private var pulseOpacity: Double = 0
    @ObservedObject private var provider = ProviderManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Pending images preview
            if !pendingImages.isEmpty {
                pendingImagesRow
            }

            // Pending files preview
            if !pendingFiles.isEmpty {
                pendingFilesRow
            }

            // Top: text field area
            TextField("Reply to Lamo", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Thin separator
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Bottom: toolbar row
            HStack(spacing: 10) {
                // Plus button — menu with Camera + Photo Library + Files
                Menu {
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }
                    Button { showPhotoPicker = true } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button { showFileImporter = true } label: {
                        Label("Files", systemImage: "doc")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .circle)

                        let attachCount = pendingImages.count + pendingFiles.count
                        if attachCount > 0 {
                            Text("\(attachCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 16, height: 16)
                                .background(.white, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Thinking mode — clear toggle with colored ring
                Button {
                    provider.objectWillChange.send()
                    provider.thinkingMode.toggle()
                } label: {
                    Image(systemName: provider.thinkingMode ? "brain.head.profile.fill" : "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(provider.thinkingMode ? .white : .white.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(provider.thinkingMode ? LamoTheme.Colors.accent.opacity(0.2) : Color.white.opacity(0.05))
                        )
                        .overlay(
                            Circle()
                                .stroke(provider.thinkingMode ? LamoTheme.Colors.accent.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel(provider.thinkingMode ? "Thinking on" : "Thinking off")

                // Model picker — same height as circle buttons
                Button { showModelPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(modelDisplayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .glassEffect(in: .capsule)
                }
                .buttonStyle(.plain)

                Spacer()

                // Send/Stop
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                } else if canSend {
                    Button(action: {
                        sendTrigger.toggle()
                        isTextFieldFocused = false
                        onSend()
                    }) {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(flexibility: .rigid), trigger: sendTrigger)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .frame(maxWidth: LamoTheme.maxContentWidth)
        .padding(.bottom, 6)
        .padding(.horizontal, 5)
        .onDrop(of: [.image, .fileURL], delegate: ChatDropDelegate(pendingImages: $pendingImages, pendingFiles: $pendingFiles))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
        .animation(.easeOut(duration: 0.15), value: canSend)
        .onChange(of: provider.isEngineReady) { _, ready in
            if ready { withAnimation { pulseOpacity = 0 } }
        }
        .onAppear {
            guard !provider.isEngineReady else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseOpacity = 1
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(image: Binding(
                get: { nil },
                set: { newImage in
                    if let img = newImage {
                        pendingImages.append(img)
                    }
                }
            ))
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPickerItems,
            maxSelectionCount: 5,
            matching: .images
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    let pending = PendingFile(url: url)
                    pendingFiles.append(pending)
                }
            case .failure(let error):
                LamoLogger.ui.error("File import failed: \(error)")
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerPopover(isPresented: $showModelPicker)
        }
    }

    private var canSend: Bool {
        provider.isEngineReady && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty || !pendingFiles.isEmpty)
    }

    private var modelDisplayName: String {
        guard let path = provider.litertLMModelPath else { return "No model" }
        return (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".litertlm", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Pending Images Preview

    private var pendingImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages.indices, id: \.self) { index in
                    PendingImageThumb(
                        image: pendingImages[index],
                        onRemove: {
                            withAnimation(.spring(response: 0.2)) {
                                if pendingImages.indices.contains(index) {
                                    pendingImages.remove(at: index)
                                }
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

// MARK: - Pending File Thumbnail

private struct PendingFileThumb: View {
    let file: PendingFile
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image(systemName: file.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 4, y: -4)
        }
    }
}

// MARK: - Pending Image Thumbnail

private struct PendingImageThumb: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 5, y: -5)
        }
    }
}

// MARK: - Drop Delegate (iPad Drag & Drop — images + files)

struct ChatDropDelegate: DropDelegate {
    @Binding var pendingImages: [UIImage]
    @Binding var pendingFiles: [PendingFile]

    func performDrop(info: DropInfo) -> Bool {
        // Try images first
        let imageProviders = info.itemProviders(for: [.image])
        for provider in imageProviders {
            _ = provider.loadObject(ofClass: UIImage.self) { image, error in
                guard let uiImage = image as? UIImage, error == nil else { return }
                let resized = uiImage.resizedForModel(maxDimension: 1024)
                DispatchQueue.main.async {
                    pendingImages.append(resized)
                }
            }
        }

        // Try file URLs
        let fileProviders = info.itemProviders(for: [.fileURL])
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url, error == nil else { return }
                DispatchQueue.main.async {
                    pendingFiles.append(PendingFile(url: url))
                }
            }
        }

        return !imageProviders.isEmpty || !fileProviders.isEmpty
    }

    func dropEntered(info: DropInfo) {}

    func dropExited(info: DropInfo) {}

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }
}

// MARK: - Image Resize Helper

extension UIImage {
    func resizedForModel(maxDimension: CGFloat) -> UIImage {
        let size = self.size
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Model Picker

struct ModelPickerPopover: View {
    @Binding var isPresented: Bool
    @ObservedObject private var provider = ProviderManager.shared
    @State private var modelInfos: [String: ModelInfo] = [:]

    private var availableModels: [(displayName: String, path: String)] {
        ProviderManager.listModels().map { filename in
            let cleanName = filename
                .replacingOccurrences(of: ".litertlm", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            let fullPath = ProviderManager.modelsDirectory.appendingPathComponent(filename).path
            return (cleanName, fullPath)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Model").font(.headline).foregroundStyle(.primary)
                Spacer()
                Button("Done") { isPresented = false }
                    .fontWeight(.semibold)
                    .foregroundStyle(LamoTheme.Colors.accent)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            // Model cards
            ScrollView {
                VStack(spacing: 10) {
                    if availableModels.isEmpty {
                        emptyState
                    } else {
                        ForEach(availableModels, id: \.path) { model in
                            modelCard(model)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Status bar
            statusBar
        }
        .background(LamoTheme.Colors.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Model Card

    private func modelCard(_ model: (displayName: String, path: String)) -> some View {
        let isSelected = provider.litertLMModelPath == model.path
        let info = modelInfos[model.path]

        return Button {
            provider.switchModel(modelPath: model.path)
            isPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Model icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? LamoTheme.Colors.accent.opacity(0.15) : Color.white.opacity(0.05))
                            .frame(width: 44, height: 44)
                        Image(systemName: "cpu")
                            .font(.system(size: 18))
                            .foregroundStyle(isSelected ? LamoTheme.Colors.accent : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.displayName)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(info?.fileSizeString ?? "On-device")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(LamoTheme.Colors.accent)
                    }
                }

                // Capability badges
                if let info {
                    HStack(spacing: 6) {
                        ForEach(capabilityBadges(for: info), id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? LamoTheme.Colors.accent.opacity(0.06) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? LamoTheme.Colors.accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            if modelInfos[model.path] == nil {
                modelInfos[model.path] = ModelInfo.from(path: model.path)
            }
        }
    }

    private func capabilityBadges(for info: ModelInfo) -> [String] {
        var badges: [String] = []
        if info.hasSpeculativeDecoding { badges.append("MTP") }
        return badges
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("No models downloaded").font(.subheadline).foregroundStyle(.tertiary)
            Text("Download a model in Settings to get started").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            if provider.isEngineReady {
                Circle().fill(LamoTheme.Colors.accent).frame(width: 6, height: 6)
                Text(modelDisplayName).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Text("· ready").font(.caption2).foregroundStyle(LamoTheme.Colors.accent.opacity(0.7))
            } else if let error = provider.engineError {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text(error).font(.caption2).foregroundStyle(.orange.opacity(0.8)).lineLimit(1)
            } else if provider.litertLMModelPath != nil {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("Loading…").font(.caption2).foregroundStyle(.secondary)
            } else {
                Circle().fill(Color.white.opacity(0.2)).frame(width: 6, height: 6)
                Text("No model selected").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color.white.opacity(0.03))
    }

    private var modelDisplayName: String {
        guard let path = provider.litertLMModelPath else { return "" }
        return (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".litertlm", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}
