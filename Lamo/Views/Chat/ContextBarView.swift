import SwiftUI

// MARK: - Context Bar (compact chip in chat)

/// A tappable chip showing context usage — sits at the top of the chat.
struct ContextBarView: View {
    let tracker: ContextTracker?
    var onTap: (() -> Void)?

    var body: some View {
        if let tracker {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 6) {
                    // Mini ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: tracker.fillRatio)
                            .stroke(ringColor(tracker), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(tracker.fillRatio * 100))")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(width: 20, height: 20)

                    // Token text
                    Text("\(ContextTracker.formatTokens(tracker.usedTokens))")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))

                    if tracker.hasDroppedMessages {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(.orange.opacity(0.8)))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private func ringColor(_ tracker: ContextTracker) -> Color {
        if tracker.fillRatio > 0.9 { return .white }
        if tracker.fillRatio > 0.7 { return .white.opacity(0.7) }
        return .white.opacity(0.4)
    }
}

// MARK: - Context Detail Sheet (bottom sheet with detents)

/// Full context breakdown — presented as a sheet from the chat.
struct ContextDetailView: View {
    let tracker: ContextTracker?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let tracker {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {

                        // ── Hero ring ──
                        heroSection(tracker)

                        // ── Used / Free / Limit row ──
                        statsRow(tracker)

                        // ── Stacked bar breakdown ──
                        breakdownBar(tracker)

                        // ── Breakdown list ──
                        breakdownList(tracker)

                        // ── Per-message list ──
                        messageList(tracker)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color.black)
                .navigationTitle("Context")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(.white)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        } else {
            ContentUnavailableView("No conversation", systemImage: "bubble.left.and.bubble.right")
        }
    }

    // MARK: - Hero Ring

    private func heroSection(_ tracker: ContextTracker) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 10)
                    .frame(width: 90, height: 90)

                Circle()
                    .trim(from: 0, to: tracker.fillRatio)
                    .stroke(ringGradient(tracker), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Text("\(Int(tracker.fillRatio * 100))%")
                        .font(.title2.monospacedDigit().bold())
                    Text("full")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }

            if tracker.hasDroppedMessages {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Older messages dropped to fit context")
                        .font(.caption)
                }
                .foregroundStyle(.gray)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Stats Row

    private func statsRow(_ tracker: ContextTracker) -> some View {
        HStack(spacing: 0) {
            statCell(title: "Used", value: ContextTracker.formatTokens(tracker.usedTokens))
            statCell(title: "Free", value: ContextTracker.formatTokens(tracker.headroom))
            statCell(title: "Limit", value: ContextTracker.formatTokens(tracker.totalLimit))
        }
        .padding(.horizontal, 4)
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.body.monospacedDigit().bold())
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stacked Breakdown Bar

    private func breakdownBar(_ tracker: ContextTracker) -> some View {
        let total = max(tracker.budgetTokens, 1)
        return VStack(alignment: .leading, spacing: 6) {
            // The bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    barSegment(
                        width: geo.size.width * (Double(tracker.systemPromptTokens) / Double(total)),
                        color: .white
                    )
                    if tracker.memoryTokens > 0 {
                        barSegment(
                            width: geo.size.width * (Double(tracker.memoryTokens) / Double(total)),
                            color: .white.opacity(0.6)
                        )
                    }
                    barSegment(
                        width: geo.size.width * (Double(tracker.messageUsages.filter(\.isInContext).reduce(0) { $0 + $1.tokenCount }) / Double(total)),
                        color: .white.opacity(0.35)
                    )
                    barSegment(
                        width: geo.size.width * (Double(512) / Double(total)),
                        color: .white.opacity(0.12)
                    )
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Legend
            HStack(spacing: 12) {
                legendDot(color: .white, label: "System")
                if tracker.memoryTokens > 0 {
                    legendDot(color: .white.opacity(0.6), label: "Memory")
                }
                legendDot(color: .white.opacity(0.35), label: "Messages")
                legendDot(color: .white.opacity(0.12), label: "Buffer")
            }
            .font(.caption2)
            .foregroundStyle(.gray)
        }
    }

    private func barSegment(width: CGFloat, color: Color) -> some View {
        color.frame(width: max(width, 0))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
        }
    }

    // MARK: - Breakdown List

    private func breakdownList(_ tracker: ContextTracker) -> some View {
        VStack(spacing: 0) {
            breakdownRow(icon: "terminal", label: "System prompt", tokens: tracker.systemPromptTokens)
            if tracker.memoryTokens > 0 {
                breakdownRow(icon: "brain", label: "Memory facts", tokens: tracker.memoryTokens)
            }
            breakdownRow(icon: "bubble.left.and.bubble.right", label: "Messages", tokens: tracker.messageUsages.filter(\.isInContext).reduce(0) { $0 + $1.tokenCount })
            breakdownRow(icon: "arrowshape.down", label: "Reply buffer", tokens: 512)
        }
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func breakdownRow(icon: String, label: String, tokens: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Text("~\(ContextTracker.formatTokens(tokens))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Message List

    private func messageList(_ tracker: ContextTracker) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Messages")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(tracker.messageUsages.filter(\.isInContext).count)/\(tracker.messageUsages.count) in context")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            ForEach(tracker.messageUsages) { msg in
                HStack(spacing: 10) {
                    // Role icon
                    Image(systemName: msg.role == "user" ? "person.fill" : "sparkle")
                        .font(.caption2)
                        .foregroundStyle(msg.isInContext ? .white : .gray.opacity(0.4))
                        .frame(width: 20)

                    // Preview
                    VStack(alignment: .leading, spacing: 1) {
                        Text(msgPreview(msg))
                            .font(.caption)
                            .foregroundStyle(msg.isInContext ? .white.opacity(0.8) : .gray.opacity(0.4))
                            .lineLimit(1)
                        Text("\(msg.charCount) chars")
                            .font(.caption2)
                            .foregroundStyle(.gray.opacity(0.5))
                    }

                    Spacer()

                    // Token count
                    Text("~\(ContextTracker.formatTokens(msg.tokenCount))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(msg.isInContext ? .gray : .gray.opacity(0.3))

                    if !msg.isInContext {
                        Image(systemName: "arrow.right.to.line")
                            .font(.caption2)
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                if msg.id != tracker.messageUsages.last?.id {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.leading, 44)
                }
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func msgPreview(_ msg: ContextTracker.MessageUsage) -> String {
        let role = msg.role == "user" ? "You" : "AI"
        return "[\(role)]"
    }

    // MARK: - Helpers

    private func ringGradient(_ tracker: ContextTracker) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [.white.opacity(0.4), .white]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * tracker.fillRatio)
        )
    }
}