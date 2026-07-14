import SwiftUI

struct ModelCardView: View {
    let model: PresetModel
    @ObservedObject var downloadManager: DownloadManager
    var isActiveModel: Bool = false
    @State private var showDeleteConfirmation = false

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
            // Header row
            HStack(alignment: .top, spacing: 12) {
                // Icon
                Image(systemName: model.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                // Info
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
                                .background(Color.white.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                // Status
                if isDownloaded && !isActiveModel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Specs row
            HStack(spacing: 16) {
                specItem(model.parameterCount, "params")
                specItem(model.fileSizeString, "size")
                specItem(model.minRAM, "RAM")
            }
            .padding(.top, 10)

            // Progress
            if isDownloading, let state = downloadState, state.totalBytes > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: state.progress)
                    HStack {
                        Text("\(state.downloadedSizeString) / \(state.totalSizeString)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(state.progressPercentage)%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 8)
            }

            // Error
            if let error = downloadState?.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            // Actions
            HStack {
                if isDownloaded {
                    if !isActiveModel {
                        Button {
                            NotificationCenter.default.post(
                                name: .selectModel,
                                object: nil,
                                userInfo: ["filename": model.filename]
                            )
                        } label: {
                            Label("Use", systemImage: "bolt.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
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
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                Text(model.license)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                downloadManager.deleteModel(model)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the model from your device.")
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
