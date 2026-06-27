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
            // Header row
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(model.accentColor == "blue"
                            ? Color.blue.opacity(0.12)
                            : Color.green.opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: model.systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(model.accentColor == "blue" ? .blue : .green)
                }

                // Name + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)

                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                        .lineLimit(isExpanded ? nil : 1)
                }

                Spacer()

                // Status
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LamoTheme.Colors.success)
                        .font(.title3)
                        .symbolEffect(.bounce, value: isDownloaded)
                } else if isDownloading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(16)

            // Stats row
            HStack(spacing: LamoTheme.Spacing.sm) {
                StatBadge(value: model.fileSizeString, icon: "internaldrive")
                StatBadge(value: model.parameterCount + " params", icon: "cpu")
                StatBadge(value: model.minRAM + " RAM", icon: "memorychip")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Expandable details
            if isExpanded {
                Divider().padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.highlights, id: \.self) { highlight in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(model.accentColor == "blue" ? .blue : .green)
                            Text(highlight)
                                .font(.subheadline)
                        }
                    }

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speed")
                                .font(.caption)
                                .foregroundStyle(LamoTheme.Colors.textSecondary)
                            Text(model.speedTier)
                                .font(.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quality")
                                .font(.caption)
                                .foregroundStyle(LamoTheme.Colors.textSecondary)
                            Text(model.qualityTier)
                                .font(.subheadline)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }

            // Progress bar
            if isDownloading, let state = downloadState, state.totalBytes > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: state.progress)
                        .tint(model.accentColor == "blue" ? .blue : .green)

                    HStack {
                        Text("\(state.downloadedSizeString) / \(state.totalSizeString)")
                            .font(.caption2)
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                        Spacer()
                        Text("\(state.progressPercentage)%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // Error
            if let error = downloadState?.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LamoTheme.Colors.error)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.error)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            Divider()

            // Action row
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Less" : "Details")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()

                if isDownloaded {
                    Button(role: .destructive) {
                        downloadManager.deleteModel(model)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                } else if isDownloading {
                    Button {
                        downloadManager.cancelDownload(model: model)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("Cancel")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        downloadManager.download(model: model)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.accentColor == "blue" ? .blue : .green)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.card, style: .continuous))
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(Capsule())
        .foregroundStyle(LamoTheme.Colors.textSecondary)
    }
}
