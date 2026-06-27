import SwiftUI

/// A card view displaying model specs with download controls.
struct ModelCardView: View {
    let model: PresetModel
    @ObservedObject var downloadManager: DownloadManager
    @State private var isExpanded = false

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
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: model.systemImage)
                            .font(.title2)
                            .foregroundStyle(model.accentColor == "blue" ? .blue : .green)

                        Text(model.displayName)
                            .font(.headline)
                    }

                    Text(model.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                Spacer()

                // Status badge
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Quick stats row
            HStack(spacing: 12) {
                StatBadge(label: "Size", value: model.fileSizeString, icon: "internaldrive")
                StatBadge(label: "Params", value: model.parameterCount, icon: "cpu")
                StatBadge(label: "RAM", value: model.minRAM, icon: "memorychip")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            // Expandable details
            if isExpanded {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Highlights")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 10)

                    ForEach(model.highlights, id: \.self) { highlight in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(model.accentColor == "blue" ? .blue : .green)
                            Text(highlight)
                                .font(.subheadline)
                        }
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.speedTier)
                                .font(.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quality")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.qualityTier)
                                .font(.subheadline)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            // Progress bar (during download)
            if isDownloading, let state = downloadState, state.totalBytes > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: state.progress)
                        .tint(model.accentColor == "blue" ? .blue : .green)

                    HStack {
                        Text("\(state.downloadedSizeString) / \(state.totalSizeString)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(state.progressPercentage)%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Error message
            if let error = downloadState?.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // Actions row
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(isExpanded ? "Less" : "Details", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                }

                Spacer()

                if isDownloaded {
                    Button(role: .destructive) {
                        downloadManager.deleteModel(model)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                    }
                } else if isDownloading {
                    Button {
                        downloadManager.cancelDownload(model: model)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.subheadline)
                    }
                } else {
                    Button {
                        downloadManager.download(model: model)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.accentColor == "blue" ? .blue : .green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
