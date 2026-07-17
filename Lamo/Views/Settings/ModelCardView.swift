import SwiftUI

struct ModelCardView: View {
    let model: PresetModel
    @ObservedObject var downloadManager: DownloadManager
    var isActiveModel: Bool = false
    var onSelect: (() -> Void)?
    @State private var showDeleteConfirmation = false
    @State private var showCellularConfirmation = false
    @State private var remoteSize: Int64? = nil

    private var downloadState: DownloadManager.DownloadState? {
        downloadManager.activeDownloads[model.filename]
    }

    private var isDownloaded: Bool {
        model.isDownloaded || downloadState?.isComplete == true
    }

    private var isDownloading: Bool {
        downloadState?.isDownloading == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.subheadline.weight(.semibold))
                        if isActiveModel {
                            Text("Active")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .glassEffect(.regular, in: .rect(cornerRadius: 6))
                        }
                    }
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isDownloaded && !isActiveModel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 16) {
                specItem(model.parameterCount, "params")
                specItem(model.displaySizeString(remoteSize: remoteSize), "size")
                specItem(model.minRAM, "RAM")
            }
            .padding(.top, 10)

            if isDownloading, let state = downloadState {
                VStack(spacing: 4) {
                    if state.totalBytes > 0 {
                        ProgressView(value: state.progress)
                    } else {
                        // Server hasn't reported Content-Length yet — indeterminate
                        ProgressView()
                            .controlSize(.small)
                    }
                    HStack {
                        Text(state.totalBytes > 0
                             ? "\(state.downloadedSizeString) / \(state.totalSizeString)"
                             : state.downloadedSizeString)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if !state.speedString.isEmpty {
                            Text("· \(state.speedString)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        if !state.etaString.isEmpty {
                            Text("· \(state.etaString)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if state.totalBytes > 0 {
                            Text("\(state.progressPercentage)%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 8)
            }

            if let error = downloadState?.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            HStack {
                if isDownloaded {
                    if !isActiveModel {
                        Button {
                            onSelect?()
                        } label: {
                            Label("Use", systemImage: "bolt.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.glassProminent)
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .foregroundStyle(.red.opacity(0.8))
                } else if isDownloading {
                    Button {
                        downloadManager.cancelDownload(model: model)
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        downloadManager.download(model: model)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.glassProminent)
                }

                Spacer()

                Text(model.license)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .task {
            // Fetch real file size from HuggingFace for not-yet-downloaded models
            guard !model.isDownloaded, remoteSize == nil else { return }
            if let size = await PresetModel.fetchRemoteSize(for: model) {
                await MainActor.run { remoteSize = size }
            }
        }
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                downloadManager.deleteModel(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the model from your device.")
        }
        .confirmationDialog(
            "Download over cellular?",
            isPresented: Binding(
                get: { downloadManager.pendingCellularDownload?.id == model.id },
                set: { if !$0 { downloadManager.cancelCellularDownload() } }
            )
        ) {
            Button("Download (\(model.displaySizeString(remoteSize: remoteSize)))") {
                downloadManager.confirmCellularDownload()
            }
            Button("Cancel", role: .cancel) {
                downloadManager.cancelCellularDownload()
            }
        } message: {
            Text("\(model.displayName) is \(model.displaySizeString(remoteSize: remoteSize)). This may use significant cellular data.")
        }
    }

    private func specItem(_ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
