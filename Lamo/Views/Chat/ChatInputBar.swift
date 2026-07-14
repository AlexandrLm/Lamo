import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
                        .accessibilityLabel("Take photo")

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                        .accessibilityLabel("Attach image")
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: Circle())

                        // Badge: image count
                        if !pendingImages.isEmpty {
                            Text("\(pendingImages.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 16, height: 16)
                                .background(LamoTheme.Colors.accent, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach image")
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
                        Circle()
                            .fill(provider.isEngineReady ? LamoTheme.Colors.accent : .orange)
                            .frame(width: 6, height: 6)
                        Text(modelDisplayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(modelDisplayName)

                Spacer()

                // Send / Stop button (white circle like the reference)
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop")
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
                    .accessibilityLabel("Send")
                    .sensoryFeedback(.impact(flexibility: .rigid), trigger: sendTrigger)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Dimmed send when empty
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
        .onDrop(of: [.image], delegate: ImageDropDelegate(pendingImages: $pendingImages))
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
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 5, y: -5)
        }
    }
}

// MARK: - Image Drop Delegate (iPad Drag & Drop)

struct ImageDropDelegate: DropDelegate {
    @Binding var pendingImages: [UIImage]

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.image])
        guard !providers.isEmpty else { return false }

        for provider in providers {
            _ = provider.loadObject(ofClass: UIImage.self) { image, error in
                guard let uiImage = image as? UIImage, error == nil else { return }
                let resized = uiImage.resizedForModel(maxDimension: 1024)
                DispatchQueue.main.async {
                    pendingImages.append(resized)
                }
            }
        }
        return true
    }

    func dropEntered(info: DropInfo) {
        // Visual feedback could be added here
    }

    func dropExited(info: DropInfo) {
        // Reset visual feedback if added
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }
}

// MARK: - Image Resize Helper

private extension UIImage {
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
                if !availableModels.isEmpty {
                    Section {
                        ForEach(availableModels, id: \.path) { model in
                            Button {
                                provider.switchModel(modelPath: model.path)
                                isPresented = false
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.06))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "cpu")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.subheadline.weight(.medium))
                                        Text("On-device")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()

                                    if provider.litertLMModelPath == model.path {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(LamoTheme.Colors.accent)
                                            .font(.title3)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        Text("Available Models")
                    }
                }

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
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
