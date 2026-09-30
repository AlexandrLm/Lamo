import SwiftUI

// MARK: - Context Bar (compact chip in chat)

/// Tappable context usage chip — sits at the top of the chat.
struct ContextBarView: View {
    let tracker: ContextTracker?
    var onTap: (() -> Void)?

    var body: some View {
        if let tracker {
            Button { onTap?() } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(fillColor(tracker))
                        .frame(width: 5, height: 5)
                    Text("\(Int(tracker.fillRatio * 100))%")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                }
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private func fillColor(_ t: ContextTracker) -> Color {
        if t.fillRatio >= 0.9 { return .orange }
        if t.fillRatio >= 0.7 { return LamoTheme.Colors.accent }
        return LamoTheme.Colors.textLow
    }
}

// MARK: - Context Detail Sheet

/// Full context breakdown — presented as a sheet from the chat.
struct ContextDetailView: View {
    let tracker: ContextTracker?
    @State private var metrics = SystemMetrics.snapshot(modelName: "", backend: "", batteryLevel: 1.0, batteryCharging: false)
    @State private var selectedSegment: MapSegment?

    var body: some View {
        if let tracker {
            ScrollView {
                LazyVStack(spacing: 28) {
                    heroSection(tracker)
                    ThinDivider()
                    mapSection(tracker)
                    ThinDivider()
                    breakdownSection(tracker)
                    ThinDivider()
                    messagesSection(tracker)
                    ThinDivider()
                    deviceStrip
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 48)
            }
            .background(LamoTheme.Colors.background)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .task {
                while !Task.isCancelled {
                    let model = ProviderManager.shared.currentModelDisplayName
                    let name = model.isEmpty ? String(localized: "None") : model
                    let backend = AppDefaults.useGPU.wrappedValue
                        ? String(localized: "GPU")
                        : String(localized: "CPU×\(AppDefaults.cpuThreadCount.wrappedValue)")
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    let rawLevel = UIDevice.current.batteryLevel
                    let level: Float = rawLevel < 0 ? 1.0 : rawLevel
                    let charging = UIDevice.current.batteryState == .charging
                        || UIDevice.current.batteryState == .full
                    let snap = await Task.detached(priority: .utility) {
                        SystemMetrics.snapshot(modelName: name, backend: backend, batteryLevel: level, batteryCharging: charging)
                    }.value
                    metrics = snap
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        } else {
            ContentUnavailableView("No conversation", systemImage: "bubble.left.and.bubble.right")
        }
    }

    // MARK: - Hero

    private func heroSection(_ t: ContextTracker) -> some View {
        let ring = ringColor(t)
        let droppedCount = t.messageUsages.filter { !$0.isInContext && !$0.isStreaming }.count
        return VStack(alignment: .leading, spacing: 12) {
            // Status line
            HStack(spacing: 8) {
                Circle()
                    .fill(ring)
                    .frame(width: 8, height: 8)
                    .shadow(color: ring.opacity(0.6), radius: 6)
                Text(statusPhrase(t))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Spacer()
                Text("\(Int(t.fillRatio * 100))%")
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
            }

            // Giant number
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ContextTracker.formatTokens(t.usedTokens))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("of \(ContextTracker.formatTokens(t.totalLimit)) tokens")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(LamoTheme.Colors.textLow)
            }

            // Meter
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LamoTheme.Colors.fillSubtle)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [ring, ring.opacity(0.55)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(6, geo.size.width * min(t.fillRatio, 1.0)), height: 6)
                }
            }
            .frame(height: 6)

            // Sub info
            HStack(spacing: 4) {
                Text("\(ContextTracker.formatTokens(t.headroom)) free · ~\(ContextTracker.formatTokens(t.reservedForReply)) reserved for reply")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                if !ProviderManager.shared.isEngineReady {
                    Text("· approximate")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.warning)
                }
            }

            // Dropped warning
            if t.hasDroppedMessages {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(droppedCount > 0
                         ? "\(droppedCount) oldest messages outside context window"
                         : "Older messages dropped to fit context")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.orange.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPhrase(_ t: ContextTracker) -> String {
        if t.hasDroppedMessages || t.fillRatio >= 0.9 { return String(localized: "Trimming history") }
        if t.fillRatio >= 0.7 { return String(localized: "Getting tight") }
        if t.fillRatio >= 0.5 { return String(localized: "Filling up") }
        return String(localized: "Plenty of room")
    }

    // MARK: - Map (context tape)

    /// Tape segment ids — shared highlight state between tape and rows.
    private enum MapSegment: String, Hashable {
        case system, memory, tools, messages, buffer
    }

    private struct TapeItem: Identifiable {
        let id: MapSegment
        let label: String
        let icon: String
        let tokens: Int
        let color: Color
    }

    private func tapeItems(_ t: ContextTracker) -> [TapeItem] {
        var items = [TapeItem(
            id: .system, label: String(localized: "System"), icon: "terminal",
            tokens: t.systemPromptTokens, color: .secondary
        )]
        if t.memoryTokens > 0 {
            items.append(TapeItem(
                id: .memory, label: String(localized: "Memory"), icon: "brain",
                tokens: t.memoryTokens, color: LamoTheme.Colors.accent
            ))
        }
        if t.toolTokens > 0 {
            let label = t.toolCountTotal > t.toolCount
                ? String(localized: "Tools (\(t.toolCount)/\(t.toolCountTotal))")
                : String(localized: "Tools (\(t.toolCount))")
            items.append(TapeItem(
                id: .tools, label: label, icon: "wrench.and.screwdriver",
                tokens: t.toolTokens, color: .orange
            ))
        }
        let msgTok = t.messageUsages.filter { $0.isInContext && !$0.isStreaming }.reduce(0) { $0 + $1.tokenCount }
        if msgTok > 0 {
            items.append(TapeItem(
                id: .messages, label: String(localized: "Messages"), icon: "bubble.left.and.bubble.right",
                tokens: msgTok, color: .blue
            ))
        }
        items.append(TapeItem(
            id: .buffer, label: String(localized: "Reply buffer"), icon: "arrowshape.down",
            tokens: t.reservedForReply, color: .clear
        ))
        return items
    }

    private func toggleSegment(_ id: MapSegment) {
        withAnimation(.easeOut(duration: 0.2)) {
            selectedSegment = (selectedSegment == id) ? nil : id
        }
    }

    private func mapSection(_ t: ContextTracker) -> some View {
        let items = tapeItems(t)
        let totalD = Double(max(t.totalLimit, 1))
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Map", icon: "map")

            // Tape: every segment proportional to the whole window.
            // Dashed = reserved for the reply, empty track = free.
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(items) { item in
                        let w = max(10, geo.size.width * Double(item.tokens) / totalD)
                        Button { toggleSegment(item.id) } label: {
                            if item.id == .buffer {
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(
                                        LamoTheme.Colors.textGhost,
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                                    .frame(width: w, height: 22)
                            } else {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(item.color)
                                    .frame(width: w, height: 22)
                            }
                        }
                        .buttonStyle(.plain)
                        .opacity(selectedSegment == nil || selectedSegment == item.id ? 1 : 0.3)
                        .accessibilityLabel("\(item.label), \(ContextTracker.formatTokens(item.tokens)) tokens")
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(LamoTheme.Colors.fillSubtle)
            )

            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(items) { item in
                    Button { toggleSegment(item.id) } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.id == .buffer ? .clear : item.color)
                                .frame(width: 7, height: 7)
                                .overlay(item.id == .buffer
                                    ? Circle().stroke(LamoTheme.Colors.textGhost, lineWidth: 1)
                                    : nil)
                            Text(item.label)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(selectedSegment == item.id
                                    ? LamoTheme.Colors.textHigh
                                    : LamoTheme.Colors.textFaint)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(ContextTracker.formatTokens(item.tokens))
                                .font(.system(size: 11, design: .monospaced).weight(.medium))
                                .foregroundStyle(selectedSegment == item.id
                                    ? LamoTheme.Colors.textHigh
                                    : LamoTheme.Colors.textMedium)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(selectedSegment == nil || selectedSegment == item.id ? 1 : 0.45)
                }
                // Free space — the empty track on the tape.
                HStack(spacing: 6) {
                    Circle()
                        .fill(LamoTheme.Colors.textGhost)
                        .frame(width: 7, height: 7)
                    Text(String(localized: "Free"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                    Spacer(minLength: 4)
                    Text(ContextTracker.formatTokens(t.headroom))
                        .font(.system(size: 11, design: .monospaced).weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Device (compact vitals strip)

    private var deviceStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Device", icon: "iphone")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    stripItem(icon: "cpu", text: metrics.modelName)
                    stripDot
                    stripItem(icon: "bolt.fill", text: metrics.backend)
                    stripDot
                    stripItem(icon: "memorychip", text: metrics.memoryString)
                    stripDot
                    stripItem(icon: metrics.batteryIcon, text: metrics.batteryString, color: batteryColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .glassEffect(.regular, in: .capsule)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stripItem(icon: String, text: String, color: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color ?? LamoTheme.Colors.textMedium)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LamoTheme.Colors.textHigh)
                .lineLimit(1)
        }
    }

    private var stripDot: some View {
        Circle()
            .fill(LamoTheme.Colors.textGhost)
            .frame(width: 4, height: 4)
    }

    // MARK: - Breakdown

    private func breakdownSection(_ t: ContextTracker) -> some View {
        let total = max(t.budgetTokens, 1)
        let msgTok = t.messageUsages.filter { $0.isInContext && !$0.isStreaming }.reduce(0) { $0 + $1.tokenCount }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Breakdown", icon: "chart.bar.fill")

            // Rows (tap highlights the matching tape segment)
            breakdownRow(icon: "terminal", label: String(localized: "System prompt"), tokens: t.systemPromptTokens, total: total, segment: .system)
            if t.memoryTokens > 0 {
                breakdownRow(icon: "brain", label: String(localized: "Memory facts"), tokens: t.memoryTokens, total: total, segment: .memory)
            }
            if t.toolTokens > 0 {
                let label = t.toolCountTotal > t.toolCount
                    ? String(localized: "Tools (\(t.toolCount)/\(t.toolCountTotal))")
                    : String(localized: "Tools (\(t.toolCount))")
                breakdownRow(icon: "wrench.and.screwdriver", label: label, tokens: t.toolTokens, total: total, segment: .tools)
            }
            breakdownRow(icon: "bubble.left.and.bubble.right", label: String(localized: "Messages"), tokens: msgTok, total: total, segment: .messages)
            breakdownRow(icon: "arrowshape.down", label: String(localized: "Reply buffer"), tokens: t.reservedForReply, total: total, isEstimate: true, segment: .buffer)

            thinDivider

            breakdownRow(icon: "sum", label: String(localized: "Total used"), tokens: t.usedTokens, total: total, bold: true)
            breakdownRow(icon: "tray.full", label: String(localized: "Context limit"), tokens: t.totalLimit, total: total, muted: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownRow(
        icon: String,
        label: String,
        tokens: Int,
        total: Int,
        isEstimate: Bool = false,
        bold: Bool = false,
        muted: Bool = false,
        segment: MapSegment? = nil
    ) -> some View {
        BreakdownRowContent(
            icon: icon, label: label, tokens: tokens, total: total,
            isEstimate: isEstimate, bold: bold, muted: muted,
            highlighted: segment.map { selectedSegment == $0 } ?? false,
            onTap: segment.map { seg in { toggleSegment(seg) } }
        )
    }

    // MARK: - Messages

    private func messagesSection(_ t: ContextTracker) -> some View {
        // Один проход вместо двух filter — мемоизируем разбиение на один body.
        var inContext: [ContextTracker.MessageUsage] = []
        var outside: [ContextTracker.MessageUsage] = []
        inContext.reserveCapacity(t.messageUsages.count)
        outside.reserveCapacity(t.messageUsages.count / 4 + 1)
        for m in t.messageUsages {
            if m.isInContext { inContext.append(m) } else { outside.append(m) }
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SectionHeader(title: "Messages", icon: "bubble.left.and.bubble.right")
                Spacer()
                Text("\(t.includedCount)/\(t.totalCountExcludingStreaming) in context")
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(LamoTheme.Colors.fillSubtle, in: Capsule())
            }

            if !inContext.isEmpty {
                messageGroup(
                    title: String(localized: "In context"),
                    color: LamoTheme.Colors.accent,
                    usages: inContext,
                    budget: t.budgetTokens
                )
            }
            if !outside.isEmpty {
                messageGroup(
                    title: String(localized: "Outside window"),
                    color: LamoTheme.Colors.textFaint,
                    usages: outside,
                    budget: t.budgetTokens
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageGroup(
        title: String,
        color: Color,
        usages: [ContextTracker.MessageUsage],
        budget: Int
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                    .tracking(0.8)
                Text("\(usages.count)")
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textGhost)
            }
            .padding(.bottom, 6)

            ForEach(Array(usages.enumerated()), id: \.element.id) { i, msg in
                if i > 0 {
                    Rectangle()
                        .fill(LamoTheme.Colors.fillSubtle)
                        .frame(height: 0.5)
                        .padding(.leading, 26)
                }
                messageRow(msg, budget: budget)
            }
        }
    }

    private func messageRow(_ msg: ContextTracker.MessageUsage, budget: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Role dot
            VStack(spacing: 0) {
                Circle()
                    .fill(
                        msg.role == "user"
                            ? LamoTheme.Colors.textLow
                            : LamoTheme.Colors.accent.opacity(0.6)
                    )
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(msg.role == "user" ? "You" : "AI")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            msg.role == "user"
                                ? LamoTheme.Colors.textFaint
                                : LamoTheme.Colors.accent.opacity(0.6)
                        )
                        .textCase(.uppercase)

                    Text("\(msg.charCount) chars")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textGhost)
                    Text("·")
                        .foregroundStyle(LamoTheme.Colors.textGhost)
                    Text(ContextTracker.formatTokens(msg.tokenCount))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textGhost)
                }

                Text(msg.preview.isEmpty ? "—" : msg.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(msg.isInContext ? LamoTheme.Colors.textMedium : LamoTheme.Colors.textFaint)
                    .lineLimit(2)

                // Share of the context budget
                GeometryReader { geo in
                    let share = budget > 0 ? min(Double(msg.tokenCount) / Double(budget), 1.0) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(LamoTheme.Colors.fillSubtle)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(msg.isInContext
                                  ? LamoTheme.Colors.accent.opacity(0.55)
                                  : LamoTheme.Colors.textGhost)
                            .frame(width: max(3, geo.size.width * share), height: 3)
                    }
                }
                .frame(height: 3)
            }

            Spacer(minLength: 8)

            // Status
            if msg.isStreaming {
                HStack(spacing: 4) {
                    Circle()
                        .fill(LamoTheme.Colors.accent)
                        .frame(width: 4, height: 4)
                    Text("now")
                        .font(.system(size: 9, design: .monospaced).weight(.medium))
                }
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(LamoTheme.Colors.accent.opacity(0.08), in: Capsule())
            } else if !msg.isInContext {
                Text("dropped")
                    .font(.system(size: 9, design: .monospaced).weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textGhost)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(LamoTheme.Colors.fillSubtle, in: Capsule())
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var thinDivider: some View {
        Rectangle()
            .fill(LamoTheme.Colors.fillMedium)
            .frame(height: 0.5)
    }

    private var batteryColor: Color {
        if metrics.batteryCharging { return .green }
        if metrics.batteryLevel < 0.2 { return .red }
        if metrics.batteryLevel < 0.4 { return .orange }
        return LamoTheme.Colors.textMedium
    }

    private func ringColor(_ t: ContextTracker) -> Color {
        if t.fillRatio >= 0.9 { return .orange }
        if t.fillRatio >= 0.7 { return LamoTheme.Colors.accent }
        return LamoTheme.Colors.textMedium
    }
}

// MARK: - Breakdown Row (Equatable, без AnyView)

private struct BreakdownRowContent: View, Equatable {
    let icon: String
    let label: String
    let tokens: Int
    let total: Int
    var isEstimate = false
    var bold = false
    var muted = false
    var highlighted = false
    var onTap: (() -> Void)?

    static func == (lhs: BreakdownRowContent, rhs: BreakdownRowContent) -> Bool {
        lhs.icon == rhs.icon && lhs.label == rhs.label && lhs.tokens == rhs.tokens
            && lhs.total == rhs.total && lhs.isEstimate == rhs.isEstimate
            && lhs.bold == rhs.bold && lhs.muted == rhs.muted
            && lhs.highlighted == rhs.highlighted
    }

    var body: some View {
        let pct = total > 0 ? Int(Double(tokens) / Double(total) * 100) : 0
        let row = HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted ? LamoTheme.Colors.textFaint : LamoTheme.Colors.accent.opacity(0.6))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13, design: .monospaced).weight(bold ? .semibold : .regular))
                .foregroundStyle(muted ? LamoTheme.Colors.textFaint : (bold ? LamoTheme.Colors.textHigh : LamoTheme.Colors.textMedium))
            if !muted {
                Text("\(pct)%")
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textGhost)
            }
            Spacer()
            Text("\(isEstimate ? "~" : "")\(ContextTracker.formatTokens(tokens))")
                .font(.system(size: 13, design: .monospaced).weight(bold ? .bold : .semibold))
                .foregroundStyle(
                    bold
                        ? LamoTheme.Colors.accent
                        : muted
                        ? LamoTheme.Colors.textFaint
                        : LamoTheme.Colors.textMedium
                )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlighted ? LamoTheme.Colors.fillSubtle : .clear)
        )
        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}

// MARK: - System Metrics

struct SystemMetrics: Sendable {
    let memoryUsedMB: Double
    let cpuPercent: Double
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float
    let batteryCharging: Bool
    let modelName: String
    let backend: String

    nonisolated static func snapshot(modelName: String, backend: String, batteryLevel: Float, batteryCharging: Bool) -> SystemMetrics {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let memResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let memMB = memResult == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0

        var cpuSize = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(cpuSize)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuSize)
            }
        }
        var cpu: Double = 0
        if cpuResult == KERN_SUCCESS {
            let user = Double(cpuInfo.cpu_ticks.0), sys = Double(cpuInfo.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2), nice = Double(cpuInfo.cpu_ticks.3)
            let total = user + sys + idle + nice
            if total > 0 { cpu = ((user + sys + nice) / total) * 100 }
        }

        return SystemMetrics(
            memoryUsedMB: memMB, cpuPercent: cpu,
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryLevel: batteryLevel,
            batteryCharging: batteryCharging,
            modelName: modelName, backend: backend
        )
    }

    var memoryString: String {
        memoryUsedMB >= 1024
            ? String(format: "%.1fG", memoryUsedMB / 1024)
            : String(format: "%.0fM", memoryUsedMB)
    }

    var cpuString: String {
        String(format: "%.0f%%", cpuPercent)
    }

    var thermalString: String {
        switch thermalState {
        case .nominal:  return String(localized: "Cool")
        case .fair:     return String(localized: "Warm")
        case .serious:  return String(localized: "Hot")
        case .critical: return String(localized: "Critical")
        @unknown default: return "—"
        }
    }

    var batteryString: String {
        batteryCharging
            ? "\(Int(batteryLevel * 100))% ⚡"
            : "\(Int(batteryLevel * 100))%"
    }

    var batteryIcon: String {
        if batteryCharging { return "battery.100percent.bolt" }
        if batteryLevel < 0.1 { return "battery.0percent" }
        if batteryLevel < 0.4 { return "battery.25percent" }
        if batteryLevel < 0.7 { return "battery.50percent" }
        if batteryLevel < 0.9 { return "battery.75percent" }
        return "battery.100percent"
    }
}
