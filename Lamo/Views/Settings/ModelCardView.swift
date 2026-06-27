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
                            .font(LamoTheme.Fonts.headline)
                    }

                    Text(model.description)
                        .font(LamoTheme.Fonts.subheadline)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                        .lineLimit(isExpanded ? nil : 2)
                }

                Spacer()

                // Status badge
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
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.top, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.md)

            // Quick stats row
            HStack(spacing: LamoTheme.Spacing.md) {
                StatBadge(label: "Size", value: model.fileSizeString, icon: "internaldrive")
                StatBadge(label: "Params", value: model.parameterCount, icon: "cpu")
                StatBadge(label: "RAM", value: model.minRAM, icon: "memorychip")
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.md)

            // Expandable details
            if isExpanded {
                Divider().padding(.horizontal, LamoTheme.Spacing.lg)

                VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
                    Text("Highlights")
                        .font(LamoTheme.Fonts.caption)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .padding(.top, LamoTheme.Spacing.md)

                    ForEach(model.highlights, id: \.self) { highlight in
                        HStack(spacing: LamoTheme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(model.accentColor == "blue" ? .blue : .green)
                            Text(highlight)
                                .font(LamoTheme.Fonts.subheadline)
                        }
                    }

                    HStack(spacing: LamoTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speed")
                                .font(LamoTheme.Fonts.caption)
                                .foregroundStyle(LamoTheme.Colors.textSecondary)
                            Text(model.speedTier)
                                .font(LamoTheme.Fonts.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quality")
                                .font(LamoTheme.Fonts.caption)
                                .foregroundStyle(LamoTheme.Colors.textSecondary)
                            Text(model.qualityTier)
                                .font(LamoTheme.Fonts.subheadline)
                        }
                    }
                    .padding(.top, LamoTheme.Spacing.xs)
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.bottom, LamoTheme.Spacing.md)
            }

            // Progress bar (during download)
            if isDownloading, let state = downloadState, state.totalBytes > 0 {
                VStack(spacing: LamoTheme.Spacing.xs) {
                    ProgressView(value: state.progress)
                        .tint(model.accentColor == "blue" ? .blue : .green)

                    HStack {
                        Text("\(state.downloadedSizeString) / \(state.totalSizeString)")
                            .font(LamoTheme.Fonts.caption2)
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                        Spacer()
                        Text("\(state.progressPercentage)%")
                            .font(LamoTheme.Fonts.caption2.monospacedDigit())
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.bottom, LamoTheme.Spacing.md)
            }

            // Error message
            if let error = downloadState?.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(LamoTheme.Colors.error)
                    Text(error)
                        .font(LamoTheme.Fonts.caption)
                        .foregroundStyle(LamoTheme.Colors.error)
                }
                .padding(.horizontal, LamoTheme.Spacing.lg)
                .padding(.bottom, LamoTheme.Spacing.md)
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
                        .font(LamoTheme.Fonts.subheadline)
                }
                .buttonStyle(.plain)

                Spacer()

                if isDownloaded {
                    Button(role: .destructive) {
                        downloadManager.deleteModel(model)
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(LamoTheme.Fonts.subheadline)
                    }
                    .buttonStyle(.plain)
                } else if isDownloading {
                    Button {
                        downloadManager.cancelDownload(model: model)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(LamoTheme.Fonts.subheadline)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        downloadManager.download(model: model)
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(LamoTheme.Fonts.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.accentColor == "blue" ? .blue : .green)
                }
            }
            .padding(LamoTheme.Spacing.lg)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.card, style: .continuous))
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(Capsule())
        .foregroundStyle(LamoTheme.Colors.textSecondary)
    }
}
