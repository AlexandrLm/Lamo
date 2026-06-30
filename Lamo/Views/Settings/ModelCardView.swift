import SwiftUI

struct ModelCardView: View {
    let model: PresetModel
    @ObservedObject var downloadManager: DownloadManager
    var isActiveModel: Bool = false
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
            // Header
            HStack(spacing: 12) {
                Image(systemName: model.systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(themeColor)
                    .frame(width: 44, height: 44)
                    .background(themeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

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

                if isActiveModel {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(themeColor)
                        .clipShape(Capsule())
                } else if isDownloaded {
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

            // Stats
            HStack(spacing: 6) {
                StatBadge(value: model.fileSizeString, icon: "internaldrive")
                StatBadge(value: model.parameterCount + " params", icon: "cpu")
                StatBadge(value: model.minRAM + " RAM", icon: "memorychip")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Capabilities
            HStack(spacing: 6) {
                ForEach(model.capabilities, id: \.self) { cap in
                    Text(cap)
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(themeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(themeColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Expandable details
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().padding(.vertical, 4)

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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("LICENSE")
                                .font(.caption2.bold())
                                .foregroundStyle(.tertiary)
                            Text(model.license)
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

            // Progress
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

            // Actions
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
                    if !isActiveModel {
                        Button {
                            withAnimation {
                                NotificationCenter.default.post(
                                    name: .selectModel,
                                    object: nil,
                                    userInfo: ["filename": model.filename]
                                )
                            }
                        } label: {
                            Label("Use", systemImage: "bolt.circle")
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(themeColor)
                    }

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
            .background(Color.clear)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
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
