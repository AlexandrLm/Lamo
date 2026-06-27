import SwiftUI

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

    private var themeColor: Color {
        model.accentColor == "blue" ? .blue : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(themeColor.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: model.systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(themeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(model.description)
                        .font(.subheadline)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                        .lineLimit(isExpanded ? nil : 1)
                }

                Spacer()

                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LamoTheme.Colors.success)
                        .font(.title3)
                        .symbolEffect(.bounce, value: isDownloaded)
                } else if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding([.top, .horizontal], 16)

            // Stats row
            HStack(spacing: 6) {
                StatBadge(value: model.fileSizeString, icon: "internaldrive")
                StatBadge(value: model.parameterCount + " params", icon: "cpu")
                StatBadge(value: model.minRAM + " RAM", icon: "memorychip")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.highlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(themeColor)
                                    .padding(.top, 3)
                                Text(highlight)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SPEED")
                                .font(.caption2.bold())
                                .foregroundStyle(.tertiary)
                            Text(model.speedTier)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("QUALITY")
                                .font(.caption2.bold())
                                .foregroundStyle(.tertiary)
                            Text(model.qualityTier)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Progress bar
            if isDownloading, let state = downloadState, state.totalBytes > 0 {
                VStack(spacing: 6) {
                    ProgressView(value: state.progress)
                        .tint(themeColor)

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
                        .font(.caption)
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Less" : "Details")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if isDownloaded {
                    Button(role: .destructive) {
                        downloadManager.deleteModel(model)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .foregroundStyle(.red)
                } else if isDownloading {
                    Button {
                        downloadManager.cancelDownload(model: model)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button {
                        downloadManager.download(model: model)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download")
                        }
                        .fontWeight(.semibold)
                    }
                    .foregroundStyle(themeColor)
                }
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.4))
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.lg, style: .continuous)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.system(.caption2, design: .rounded).weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(uiColor: .quaternarySystemFill))
        .clipShape(Capsule())
        .foregroundStyle(LamoTheme.Colors.textSecondary)
    }
}
