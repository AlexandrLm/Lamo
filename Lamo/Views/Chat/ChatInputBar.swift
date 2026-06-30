import SwiftUI
import PhotosUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var pendingImages: [UIImage]
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    @State private var showModelPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var sendTrigger = false
    @ObservedObject private var provider = ProviderManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Pending images preview
            if !pendingImages.isEmpty {
                pendingImagesRow
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
                // Plus button — menu with Camera + Photo Library
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: Circle())

                        // Badge: image count
                        if !pendingImages.isEmpty {
                            Text("\(pendingImages.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 16, height: 16)
                                .background(LamoTheme.Colors.accent, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onChange(of: photoPickerItems) {
                    guard !photoPickerItems.isEmpty else { return }
                    Task {
                        for item in photoPickerItems {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                pendingImages.append(image)
                            }
                        }
                        photoPickerItems = []
                    }
                }

                // Model selector pill
                Button {
                    showModelPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(modelDisplayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if provider.isEngineReady {
                            Text("Ready")
                                .font(.system(size: 11))
                                .foregroundStyle(LamoTheme.Colors.accent)
                        } else {
                            Text("Loading")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Microphone button
                Button {} label: {
                    Image(systemName: "microphone")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)

                // Send / Stop button (white circle like the reference)
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
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
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(flexibility: .rigid), trigger: sendTrigger)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Dimmed send when empty
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
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
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isStreaming)
        .animation(.easeOut(duration: 0.15), value: canSend)
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(isPresented: $showModelPicker)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
    }

    private var modelDisplayName: String {
        let name = provider.currentModelDisplayName
        return name.isEmpty ? "No Model" : name
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
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
                    .font(.system(size: 16))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 5, y: -5)
        }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var provider = ProviderManager.shared

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
        NavigationStack {
            List {
                Section("Providers") {
                    Button {
                        provider.switchModel(provider: .appleIntelligence)
                        isPresented = false
                    } label: {
                        HStack {
                            Label("Apple Intelligence", systemImage: "apple.logo")
                            Spacer()
                            if provider.selectedProvider == .appleIntelligence {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(LamoTheme.Colors.accent)
                            }
                        }
                    }
                    .tint(.primary)
                }

                if !availableModels.isEmpty {
                    Section("On-Device Models") {
                        ForEach(availableModels, id: \.path) { model in
                            Button {
                                provider.switchModel(provider: .litertLM, modelPath: model.path)
                                isPresented = false
                            } label: {
                                HStack {
                                    Label(model.displayName, systemImage: "cpu")
                                    Spacer()
                                    if provider.selectedProvider == .litertLM &&
                                        provider.litertLMModelPath == model.path {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(LamoTheme.Colors.accent)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                // Thinking mode
                if provider.selectedProvider == .litertLM {
                    Section {
                        Toggle(isOn: Binding(
                            get: { provider.thinkingMode },
                            set: { provider.thinkingMode = $0 }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Thinking Mode")
                                    Text("Extended reasoning before answering")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            } icon: {
                                Image(systemName: "brain")
                                    .foregroundStyle(provider.thinkingMode ? LamoTheme.Colors.accent : .secondary)
                            }
                        }
                        .tint(LamoTheme.Colors.accent)
                    }
                }

                // Engine status
                if provider.selectedProvider == .litertLM {
                    Section {
                        if provider.isEngineReady {
                            Label("Model loaded", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if let error = provider.engineError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        } else if provider.litertLMModelPath != nil {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Loading…").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
