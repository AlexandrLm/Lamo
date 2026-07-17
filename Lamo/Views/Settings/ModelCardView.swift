import SwiftUI

/// Catalog card for downloadable models — richer specs, accent color on active state.
struct ModelCardView: View {
    let model: PresetModel
    @ObservedObject var downloadManager: DownloadManager
    var isActiveModel: Bool = false
    var onSelect: (() -> Void)?
    @State private var showDeleteConfirmation = false
    @State private var remoteSize: Int64? = nil

    private var downloadState: DownloadManager.DownloadState? {
        downloadManager.activeDownloads[model.filename]
    }
    private var isDownloaded: Bool { model.isDownloaded || downloadState?.isComplete == true }
    private var isDownloading: Bool { downloadState?.isDownloading == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: icon + name + status
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    if isActiveModel {
                        Circle()
                            .stroke(LamoTheme.Colors.accent, lineWidth: 1.5)
                            .frame(width: 36, height: 36)
                    }
                    Image(systemName: model.systemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(isActiveModel ? LamoTheme.Colors.accent : .white.opacity(0.4))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white)
                        if isActiveModel {
                            Text("ACTIVE")
                                .font(.system(size: 7, design: .monospaced).weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(LamoTheme.Colors.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(model.description)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isDownloaded && !isActiveModel {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
                } else if isDownloading {
                    ProgressView().controlSize(.small).tint(.white.opacity(0.5))
                }
            }

            // Specs row
            HStack(spacing: 12) {
                specTag(icon: "cpu.fill", value: model.parameterCount)
                specTag(icon: "internaldrive", value: model.displaySizeString(remoteSize: remoteSize))
                specTag(icon: "memorychip", value: model.minRAM)
            }
            .padding(.top, 10)

            // Download progress
            if isDownloading, let state = downloadState {
                VStack(spacing: 4) {
                    if state.totalBytes > 0 {
                        ProgressView(value: state.progress).tint(LamoTheme.Colors.accent)
                    } else {
                        ProgressView().controlSize(.small).tint(.white.opacity(0.4))
                    }
                    HStack {
                        Text(state.totalBytes > 0
                             ? "\(state.downloadedSizeString) / \(state.totalSizeString)"
                             : state.downloadedSizeString)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                        if !state.speedString.isEmpty {
                            Text("· \(state.speedString)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer()
                        if state.totalBytes > 0 {
                            Text("\(state.progressPercentage)%")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 8)
            }

            if let error = downloadState?.error {
                Text(error)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(.top, 6)
            }

            // Divider + actions
            Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.vertical, 10)

            HStack {
                if isDownloaded {
                    if !isActiveModel {
                        Button { onSelect?() } label: {
                            Label("Use", systemImage: "bolt.fill")
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    Button(role: .destructive) { showDeleteConfirmation = true } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(.red.opacity(0.6))
                } else if isDownloading {
                    Button { downloadManager.cancelDownload(model: model) } label: {
                        Label("Cancel", systemImage: "xmark")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                } else {
                    Button { downloadManager.download(model: model) } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.system(.caption, design: .monospaced).weight(.medium))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.glassProminent)
                }
                Spacer()
                Text(model.license)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .task {
            guard !model.isDownloaded, remoteSize == nil else { return }
            if let size = await PresetModel.fetchRemoteSize(for: model) {
                await MainActor.run { remoteSize = size }
            }
        }
        .confirmationDialog("Delete \(model.displayName)?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { downloadManager.deleteModel(model) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This will remove the model from your device.") }
        .confirmationDialog(
            "Download over cellular?",
            isPresented: Binding(
                get: { downloadManager.pendingCellularDownload?.id == model.id },
                set: { if !$0 { downloadManager.cancelCellularDownload() } }
            )
        ) {
            Button("Download Anyway") { downloadManager.confirmCellularDownload() }
            Button("Cancel", role: .cancel) { downloadManager.cancelCellularDownload() }
        } message: {
            Text("\(model.displayName) is \(model.displaySizeString(remoteSize: remoteSize)). This may use significant cellular data.")
        }
    }

    private func specTag(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
