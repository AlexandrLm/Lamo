import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os

// MARK: - Constants

private enum Constants {
    static let barCornerRadius: CGFloat = 22
    static let buttonSize: CGFloat = 32
    static let maxPhotoSelection = 5
    static let maxImageDimension: CGFloat = 1024
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
    @State private var showModelPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var sendCount = 0
    @State private var pulseOpacity: Double = 0
    @ObservedObject private var provider = ProviderManager.shared

    var body: some View {
        VStack(spacing: 0) {
            if !pendingImages.isEmpty { pendingImagesRow }
            if !pendingFiles.isEmpty { pendingFilesRow }

            TextField("Reply to Lamo", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            // Toolbar
            HStack(spacing: 10) {
                plusButton
                thinkingButton
                modelButton
                Spacer()
                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Constants.barCornerRadius))
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
        .sheet(isPresented: $showModelPicker) {
            ModelPickerPopover(isPresented: $showModelPicker)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(onCapture: { pendingImages.append(PendingImage(image: $0)) })
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
            Task {
                for item in photoPickerItems {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            pendingImages.append(PendingImage(image: image))
                        }
                    } catch {
                        LamoLogger.ui.error("Photo picker load failed: \(error)")
                    }
                }
                photoPickerItems = []
            }
        }
    }

    // MARK: - Plus button

    private var plusButton: some View {
        Menu {
            Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill") }
            Button { showPhotoPicker = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
            Button { showFileImporter = true } label: { Label("Files", systemImage: "doc") }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
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
    }

    // MARK: - Thinking button

    private var thinkingButton: some View {
        Button {
            provider.thinkingMode.toggle()
        } label: {
            Image(systemName: provider.thinkingMode ? "brain.head.profile.fill" : "brain.head.profile")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(provider.thinkingMode ? .white : .white.opacity(0.3))
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(provider.thinkingMode
                            ? LamoTheme.Colors.accent.opacity(0.2)
                            : Color.white.opacity(0.05))
                )
                .overlay(
                    Circle()
                        .stroke(provider.thinkingMode
                            ? LamoTheme.Colors.accent.opacity(0.6)
                            : Color.white.opacity(0.1),
                            lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    // MARK: - Model button

    private var modelButton: some View {
        Button { showModelPicker = true } label: {
            HStack(spacing: 6) {
                if !provider.isEngineReady && provider.litertLMModelPath != nil {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .tint(.white.opacity(0.5))
                }
                Text(provider.currentModelDisplayName.isEmpty ? "No model" : provider.currentModelDisplayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(modelTextColor)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
            .frame(height: Constants.buttonSize)
            .glassEffect(in: .capsule)
            .overlay(
                Capsule()
                    .stroke(modelBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send/Stop button

    @ViewBuilder
    private var sendButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        } else if canSend {
            Button(action: {
                sendCount += 1
                isTextFieldFocused = false
                onSend()
            }) {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: sendCount)
            .transition(.scale.combined(with: .opacity))
        } else {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(Color.white.opacity(0.1), in: Circle())
        }
    }

    // MARK: - Computed

    private var canSend: Bool {
        provider.isEngineReady
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !pendingImages.isEmpty
                || !pendingFiles.isEmpty)
    }

    private var modelTextColor: Color {
        if provider.isEngineReady { return LamoTheme.Colors.accent.opacity(0.85) }
        if provider.engineError != nil { return .orange.opacity(0.7) }
        if provider.litertLMModelPath != nil { return .white.opacity(0.5) }
        return .white.opacity(0.3)
    }

    private var modelBorderColor: Color {
        if provider.isEngineReady { return LamoTheme.Colors.accent.opacity(0.5) }
        if provider.engineError != nil { return .orange.opacity(0.4) }
        return .clear
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

// MARK: - Model Picker Sheet

struct ModelPickerPopover: View {
    @Binding var isPresented: Bool
    @ObservedObject private var provider = ProviderManager.shared
    @State private var modelInfos: [String: ModelInfo] = [:]
    @State private var availableModels: [(displayName: String, path: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model").font(.headline).foregroundStyle(.primary)
                Spacer()
                Button("Done") { isPresented = false }
                    .fontWeight(.semibold).foregroundStyle(LamoTheme.Colors.accent)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    if availableModels.isEmpty { emptyState }
                    else {
                        ForEach(availableModels, id: \.path) { model in modelCard(model) }
                    }
                }
                .padding(.horizontal, 16)
            }
            statusBar
        }
        .background(LamoTheme.Colors.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            availableModels = ProviderManager.listModels().map { filename in
                let fullPath = ProviderManager.modelsDirectory.appendingPathComponent(filename).path
                return (ProviderManager.displayName(forModelPath: filename), fullPath)
            }
        }
    }

    private func modelCard(_ model: (displayName: String, path: String)) -> some View {
        let isSelected = provider.litertLMModelPath == model.path
        let info = modelInfos[model.path]

        return Button {
            provider.switchModel(modelPath: model.path)
            isPresented = false
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
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
                            .font(.title3).foregroundStyle(LamoTheme.Colors.accent)
                    }
                }
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
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? LamoTheme.Colors.accent.opacity(0.06) : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? LamoTheme.Colors.accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onAppear {
            if modelInfos[model.path] == nil { modelInfos[model.path] = ModelInfo.from(path: model.path) }
        }
    }

    private func capabilityBadges(for info: ModelInfo) -> [String] {
        var badges: [String] = []
        if info.hasSpeculativeDecoding { badges.append("MTP") }
        return badges
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("No models downloaded").font(.subheadline).foregroundStyle(.tertiary)
            Text("Download a model in Settings to get started")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(.vertical, 60).frame(maxWidth: .infinity)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if provider.isEngineReady {
                Circle().fill(LamoTheme.Colors.accent).frame(width: 6, height: 6)
                Text(provider.currentModelDisplayName)
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
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
    }
}
