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
                        .foregroundStyle(.white.opacity(0.5))
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
        return .white.opacity(0.4)
    }
}

// MARK: - Context Detail Sheet

/// Full context breakdown — presented as a sheet from the chat.
struct ContextDetailView: View {
    let tracker: ContextTracker?
    @Environment(\.dismiss) private var dismiss
    @State private var metrics = SystemMetrics.snapshot()
    @State private var metricsTimer: Timer?

    var body: some View {
        if let tracker {
            NavigationStack {
                ScrollView {
                    VStack(spacing: LamoTheme.Spacing.md) {
                        heroCard(tracker)
                        systemCard
                        breakdownCard(tracker)
                        messageCard(tracker)
                    }
                    .padding(.horizontal, LamoTheme.Spacing.lg)
                    .padding(.top, LamoTheme.Spacing.md)
                    .padding(.bottom, LamoTheme.Spacing.xxxl)
                }
                .navigationTitle("Context")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(LamoTheme.Colors.background)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear {
                metrics = SystemMetrics.snapshot()
                metricsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                    metrics = SystemMetrics.snapshot()
                }
            }
            .onDisappear { metricsTimer?.invalidate() }
        } else {
            ContentUnavailableView("No conversation", systemImage: "bubble.left.and.bubble.right")
        }
    }

    // MARK: - Hero

    private func heroCard(_ t: ContextTracker) -> some View {
        VStack(spacing: LamoTheme.Spacing.lg) {
            // Ring
            ZStack {
                Circle()
                    .trim(from: 0, to: t.fillRatio)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [ringColor(t), ringColor(t).opacity(0.3)]),
                            center: .center, startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * max(t.fillRatio, 0.01))
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 112, height: 112)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor(t).opacity(0.3), radius: 8)

                VStack(spacing: 1) {
                    Text("\(Int(t.fillRatio * 100))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("% full")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .padding(.top, LamoTheme.Spacing.sm)

            // Stats
            HStack(spacing: 0) {
                statCell(icon: "arrow.up.doc", value: ContextTracker.formatTokens(t.usedTokens), label: "Used")
                statCell(icon: "tray", value: ContextTracker.formatTokens(t.headroom), label: "Free")
                statCell(icon: "drop.halffull", value: ContextTracker.formatTokens(t.totalLimit), label: "Limit")
            }

            if t.hasDroppedMessages {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text("Older messages dropped to fit context")
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(.orange.opacity(0.6))
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // MARK: - System Metrics

    private var systemCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("System", icon: "gauge.with.dots.needle.50percent")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: LamoTheme.Spacing.sm) {
                metricCell(icon: "cpu", value: metrics.modelName, label: "MODEL", color: LamoTheme.Colors.accent.opacity(0.8))
                metricCell(icon: "bolt.fill", value: metrics.backend, label: "BACKEND", color: .white.opacity(0.6))
                metricCell(icon: metrics.batteryIcon, value: metrics.batteryString, label: "BATTERY", color: batteryColor)
                metricCell(icon: "memorychip", value: metrics.memoryString, label: "MEMORY", color: memoryColor)
                metricCell(icon: "cpu", value: metrics.cpuString, label: "CPU", color: cpuColor)
                metricCell(icon: "thermometer.medium", value: metrics.thermalString, label: "THERMAL", color: thermalColor)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9))
                Text(value)
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.sm))
    }

    private var memoryColor: Color {
        if metrics.memoryUsedMB > 3500 { return .orange }
        if metrics.memoryUsedMB > 2000 { return LamoTheme.Colors.accent }
        return .white.opacity(0.6)
    }

    private var cpuColor: Color {
        if metrics.cpuPercent > 80 { return .orange }
        if metrics.cpuPercent > 40 { return LamoTheme.Colors.accent }
        return .white.opacity(0.6)
    }

    private var thermalColor: Color {
        switch metrics.thermalState {
        case .critical, .serious: return .red
        case .fair: return .orange
        case .nominal: return LamoTheme.Colors.accent
        @unknown default: return .white.opacity(0.4)
        }
    }

    private var batteryColor: Color {
        if metrics.batteryCharging { return .green }
        if metrics.batteryLevel < 0.2 { return .red }
        if metrics.batteryLevel < 0.4 { return .orange }
        return .white.opacity(0.6)
    }

    // MARK: - Breakdown

    private func breakdownCard(_ t: ContextTracker) -> some View {
        let total = max(t.budgetTokens, 1)
        let sysW = Double(t.systemPromptTokens) / Double(total)
        let memW = Double(t.memoryTokens) / Double(total)
        let toolW = Double(t.toolTokens) / Double(total)
        let msgTok = t.messageUsages.filter { $0.isInContext && !$0.isStreaming }.reduce(0) { $0 + $1.tokenCount }
        let msgW = Double(msgTok) / Double(total)
        let bufW = Double(t.reservedForReply) / Double(total)
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Breakdown", icon: "chart.bar.fill")

            GeometryReader { geo in
                HStack(spacing: 1) {
                    if sysW > 0 { Rectangle().fill(.white).frame(width: geo.size.width * sysW) }
                    if memW > 0 { Rectangle().fill(LamoTheme.Colors.accent.opacity(0.6)).frame(width: geo.size.width * memW) }
                    if toolW > 0 { Rectangle().fill(.orange.opacity(0.5)).frame(width: geo.size.width * toolW) }
                    if msgW > 0 { Rectangle().fill(.white.opacity(0.3)).frame(width: geo.size.width * msgW) }
                    if bufW > 0 { Rectangle().fill(.white.opacity(0.1)).frame(width: geo.size.width * bufW) }
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.bottom, LamoTheme.Spacing.sm)

            HStack(spacing: 14) {
                legendDot(color: .white, label: "System")
                if t.memoryTokens > 0 { legendDot(color: LamoTheme.Colors.accent, label: "Memory") }
                if t.toolTokens > 0 { legendDot(color: .orange, label: "Tools") }
                legendDot(color: .white.opacity(0.3), label: "Messages")
                legendDot(color: .white.opacity(0.1), label: "Buffer")
            }

            thinDivider.padding(.vertical, LamoTheme.Spacing.sm)

            breakdownRow(icon: "terminal", label: "System prompt", value: t.systemPromptTokens)
            if t.memoryTokens > 0 {
                breakdownRow(icon: "brain", label: "Memory facts", value: t.memoryTokens)
            }
            if t.toolTokens > 0 {
                let label = t.toolCountTotal > t.toolCount
                    ? "Tools (\(t.toolCount)/\(t.toolCountTotal) active)"
                    : "Tools (\(t.toolCount))"
                breakdownRow(icon: "wrench.and.screwdriver", label: label, value: t.toolTokens)
            }
            breakdownRow(icon: "bubble.left.and.bubble.right", label: "Messages", value: msgTok)
            breakdownRow(icon: "arrowshape.down", label: "Reply buffer", value: t.reservedForReply, isEstimate: true)
            thinDivider.padding(.vertical, LamoTheme.Spacing.sm)
            breakdownRow(icon: "sum", label: "Total used", value: t.usedTokens)
            breakdownRow(icon: "tray.full", label: "Budget limit", value: t.totalLimit)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownRow(icon: String, label: String, value: Int, isEstimate: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
                .frame(width: 18)
            Text(label)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            Text("\(isEstimate ? "~" : "")\(ContextTracker.formatTokens(value))")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical, 8)
    }

    // MARK: - Messages

    private func messageCard(_ t: ContextTracker) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionLabel("Messages", icon: "bubble.left.and.bubble.right")
                Spacer()
                Text("\(t.includedCount)/\(t.totalCountExcludingStreaming) in context")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.bottom, LamoTheme.Spacing.sm)

            ForEach(Array(t.messageUsages.enumerated()), id: \.element.id) { i, msg in
                if i > 0 { thinDivider }
                messageRow(msg)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageRow(_ msg: ContextTracker.MessageUsage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Role indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(msg.role == "user" ? .white.opacity(0.3) : LamoTheme.Colors.accent.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }

            VStack(alignment: .leading, spacing: 3) {
                // Role label
                Text(msg.role == "user" ? "You" : "AI")
                    .font(.system(size: 9, design: .monospaced).weight(.bold))
                    .foregroundStyle(msg.role == "user" ? .white.opacity(0.25) : LamoTheme.Colors.accent.opacity(0.5))
                    .textCase(.uppercase)

                // Preview
                Text(msg.preview.isEmpty ? "—" : msg.preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(msg.isInContext ? .white.opacity(0.8) : .white.opacity(0.3))
                    .lineLimit(2)

                // Meta
                HStack(spacing: 6) {
                    Text("\(msg.charCount) chars")
                    Text("·")
                    Text(ContextTracker.formatTokens(msg.tokenCount))
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.22))
            }

            Spacer(minLength: 0)

            if msg.isStreaming {
                HStack(spacing: 3) {
                    Circle().fill(LamoTheme.Colors.accent).frame(width: 5, height: 5)
                    Text("now").font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.6))
            } else if !msg.isInContext {
                Text("dropped")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.15))
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LamoTheme.Colors.accent)
            Text(text)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.8))
                .textCase(.uppercase)
        }
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 7))
                Text(label)
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func ringColor(_ t: ContextTracker) -> Color {
        if t.fillRatio >= 0.9 { return .orange }
        if t.fillRatio >= 0.7 { return LamoTheme.Colors.accent }
        return .white.opacity(0.5)
    }

    private var thinDivider: some View {
        Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - System Metrics

/// Live system metrics for the context detail sheet.
struct SystemMetrics {
    let memoryUsedMB: Double
    let cpuPercent: Double
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float
    let batteryCharging: Bool
    let modelName: String
    let backend: String

    var memoryString: String {
        if memoryUsedMB >= 1024 { return String(format: "%.1fG", memoryUsedMB / 1024) }
        return String(format: "%.0fM", memoryUsedMB)
    }
    var cpuString: String { String(format: "%.0f%%", cpuPercent) }
    var batteryString: String { String(format: "%.0f%%", batteryLevel * 100) }
    var batteryIcon: String { batteryCharging ? "battery.100.bolt" : batteryLevel >= 0.8 ? "battery.75" : batteryLevel >= 0.4 ? "battery.50" : "battery.25" }

    var thermalString: String {
        switch thermalState {
        case .nominal:  return "Cool"
        case .fair:     return "Warm"
        case .serious:  return "Hot"
        case .critical: return "Critical"
        @unknown default: return "—"
        }
    }

    static func snapshot() -> SystemMetrics {
        // Memory
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / 4)
        let memResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let memMB = memResult == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0

        // CPU
        var cpuSize = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / 4)
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

        // Battery
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batt = UIDevice.current.batteryLevel
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

        // Model
        let pm = ProviderManager.shared
        let modelName: String = {
            let name = pm.currentModelDisplayName
            return name.isEmpty ? "None" : name
        }()
        let gpu = AppDefaults.useGPU.wrappedValue
        let backend = gpu ? "GPU" : "CPU×\(AppDefaults.cpuThreadCount.wrappedValue)"

        return SystemMetrics(
            memoryUsedMB: memMB, cpuPercent: cpu,
            thermalState: ProcessInfo.processInfo.thermalState,
            batteryLevel: batt < 0 ? 1.0 : batt,
            batteryCharging: charging,
            modelName: modelName, backend: backend
        )
    }
}
