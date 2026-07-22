import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import os
import Speech

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
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var sendCount = 0
    @State private var pulseOpacity: Double = 0
    @StateObject private var speechRecognizer = SpeechRecognizer()
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
                micButton
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
        .onChange(of: speechRecognizer.transcribedText) { _, newValue in
            text = newValue
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

    // MARK: - Microphone button

    private var micButton: some View {
        Button {
            if speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
            } else {
                Task {
                    let authorized = await speechRecognizer.requestAuthorization()
                    guard authorized else { return }
                    try? speechRecognizer.startRecording()
                }
            }
        } label: {
            Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(speechRecognizer.isRecording ? LamoTheme.Colors.accent : .white.opacity(0.3))
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .background(
                    Circle()
                        .fill(speechRecognizer.isRecording
                            ? LamoTheme.Colors.accent.opacity(0.2)
                            : Color.white.opacity(0.05))
                )
                .overlay(
                    Circle()
                        .stroke(speechRecognizer.isRecording
                            ? LamoTheme.Colors.accent.opacity(0.6)
                            : Color.white.opacity(0.1),
                            lineWidth: 1.5)
                )
                .animation(.easeInOut(duration: 0.2), value: speechRecognizer.isRecording)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
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
