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
                    VStack(spacing: 28) {
                        heroSection(tracker)
                        Divider().opacity(0.08)
                        systemSection
                        Divider().opacity(0.08)
                        breakdownSection(tracker)
                        Divider().opacity(0.08)
                        messagesSection(tracker)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
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

    private func heroSection(_ t: ContextTracker) -> some View {
        VStack(spacing: 24) {
            // Ring
            ZStack {
                // Track
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 12)
                    .frame(width: 148, height: 148)

                // Filled arc
                Circle()
                    .trim(from: 0, to: t.fillRatio)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                LamoTheme.Colors.accent,
                                LamoTheme.Colors.accent.opacity(0.7),
                                LamoTheme.Colors.accent.opacity(0.3)
                            ]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * max(t.fillRatio, 0.01))
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 148, height: 148)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: LamoTheme.Colors.accent.opacity(0.4), radius: 16, y: 0)

                // Glow dot at end of arc
                if t.fillRatio > 0.01 {
                    Circle()
                        .fill(LamoTheme.Colors.accent)
                        .frame(width: 8, height: 8)
                        .offset(y: -74)
                        .rotationEffect(.degrees(360 * t.fillRatio))
                        .blur(radius: 4)
                        .opacity(0.7)
                }

                // Center text
                VStack(spacing: 0) {
                    Text("\(Int(t.fillRatio * 100))")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LamoTheme.Colors.accent.opacity(0.7))
                }
            }
            .padding(.top, 8)

            // Stats row
            HStack(spacing: 12) {
                statPill(
                    icon: "arrow.up.doc",
                    value: ContextTracker.formatTokens(t.usedTokens),
                    label: "Used",
                    color: t.fillRatio >= 0.9 ? .orange : LamoTheme.Colors.accent
                )
                statPill(
                    icon: "tray",
                    value: ContextTracker.formatTokens(t.headroom),
                    label: "Free",
                    color: .white.opacity(0.5)
                )
                statPill(
                    icon: "drop.halffull",
                    value: ContextTracker.formatTokens(t.totalLimit),
                    label: "Limit",
                    color: .white.opacity(0.3)
                )
            }

            // Dropped warning
            if t.hasDroppedMessages {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Older messages dropped to fit context")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.orange.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.orange.opacity(0.08), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - System

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                Text("System".uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.8))
                    .tracking(1)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                spacing: 10
            ) {
                metricTile(
                    icon: "cpu",
                    value: metrics.modelName,
                    label: "Model",
                    color: LamoTheme.Colors.accent.opacity(0.9)
                )
                metricTile(
                    icon: "bolt.fill",
                    value: metrics.backend,
                    label: "Backend",
                    color: .white.opacity(0.6)
                )
                metricTile(
                    icon: metrics.batteryIcon,
                    value: metrics.batteryString,
                    label: "Battery",
                    color: batteryColor
                )
                metricTile(
                    icon: "memorychip",
                    value: metrics.memoryString,
                    label: "Memory",
                    color: memoryColor
                )
                metricTile(
                    icon: "cpu",
                    value: metrics.cpuString,
                    label: "CPU",
                    color: cpuColor
                )
                metricTile(
                    icon: "thermometer.medium",
                    value: metrics.thermalString,
                    label: "Thermal",
                    color: thermalColor
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricTile(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color)
                .frame(height: 18)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Breakdown

    private func breakdownSection(_ t: ContextTracker) -> some View {
        let total = max(t.budgetTokens, 1)
        let msgTok = t.messageUsages.filter { $0.isInContext && !$0.isStreaming }.reduce(0) { $0 + $1.tokenCount }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                Text("Breakdown".uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.8))
                    .tracking(1)
            }

            // Stacked bar
            barChart(t, total: total)

            // Legend
            HStack(spacing: 16) {
                legendDot(color: .white, label: "System")
                if t.memoryTokens > 0 {
                    legendDot(color: LamoTheme.Colors.accent, label: "Memory")
                }
                if t.toolTokens > 0 {
                    legendDot(color: .orange, label: "Tools")
                }
                legendDot(color: .white.opacity(0.3), label: "Messages")
                legendDot(color: .white.opacity(0.1), label: "Buffer")
            }

            thinDivider

            // Rows
            breakdownRow(icon: "terminal", label: "System prompt", tokens: t.systemPromptTokens, total: total)
            if t.memoryTokens > 0 {
                breakdownRow(icon: "brain", label: "Memory facts", tokens: t.memoryTokens, total: total)
            }
            if t.toolTokens > 0 {
                let label = t.toolCountTotal > t.toolCount
                    ? "Tools (\(t.toolCount)/\(t.toolCountTotal))"
                    : "Tools (\(t.toolCount))"
                breakdownRow(icon: "wrench.and.screwdriver", label: label, tokens: t.toolTokens, total: total)
            }
            breakdownRow(icon: "bubble.left.and.bubble.right", label: "Messages", tokens: msgTok, total: total)
            breakdownRow(icon: "arrowshape.down", label: "Reply buffer", tokens: t.reservedForReply, total: total, isEstimate: true)

            thinDivider

            breakdownRow(icon: "sum", label: "Total used", tokens: t.usedTokens, total: total, bold: true)
            breakdownRow(icon: "tray.full", label: "Budget limit", tokens: t.totalLimit, total: total, muted: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barChart(_ t: ContextTracker, total: Int) -> some View {
        let totalD = Double(max(total, 1))
        let sysW = Double(t.systemPromptTokens) / totalD
        let memW = Double(t.memoryTokens) / totalD
        let toolW = Double(t.toolTokens) / totalD
        let msgTok = t.messageUsages.filter { $0.isInContext && !$0.isStreaming }.reduce(0) { $0 + $1.tokenCount }
        let msgW = Double(msgTok) / totalD
        let bufW = Double(t.reservedForReply) / totalD

        return GeometryReader { geo in
            HStack(spacing: 2) {
                if sysW > 0 {
                    Rectangle().fill(.white.opacity(0.9))
                        .frame(width: geo.size.width * sysW)
                }
                if memW > 0 {
                    Rectangle().fill(LamoTheme.Colors.accent.opacity(0.8))
                        .frame(width: geo.size.width * memW)
                }
                if toolW > 0 {
                    Rectangle().fill(.orange.opacity(0.7))
                        .frame(width: geo.size.width * toolW)
                }
                if msgW > 0 {
                    Rectangle().fill(.white.opacity(0.25))
                        .frame(width: geo.size.width * msgW)
                }
                if bufW > 0 {
                    Rectangle().fill(.white.opacity(0.08))
                        .frame(width: geo.size.width * bufW)
                }
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func breakdownRow(
        icon: String,
        label: String,
        tokens: Int,
        total: Int,
        isEstimate: Bool = false,
        bold: Bool = false,
        muted: Bool = false
    ) -> some View {
        let pct = total > 0 ? Int(Double(tokens) / Double(total) * 100) : 0
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(muted ? .white.opacity(0.3) : LamoTheme.Colors.accent.opacity(0.6))
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, design: .monospaced).weight(bold ? .semibold : .regular))
                .foregroundStyle(muted ? .white.opacity(0.3) : .white.opacity(bold ? 0.9 : 0.7))

            if !muted {
                Text("\(pct)%")
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.2))
            }

            Spacer()

            Text("\(isEstimate ? "~" : "")\(ContextTracker.formatTokens(tokens))")
                .font(.system(size: 13, design: .monospaced).weight(bold ? .bold : .semibold))
                .foregroundStyle(
                    bold
                        ? LamoTheme.Colors.accent
                        : muted
                        ? .white.opacity(0.3)
                        : .white.opacity(0.6)
                )
        }
        .padding(.vertical, 6)
    }

    // MARK: - Messages

    private func messagesSection(_ t: ContextTracker) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LamoTheme.Colors.accent)
                Text("Messages".uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.8))
                    .tracking(1)
                Spacer()
                Text("\(t.includedCount)/\(t.totalCountExcludingStreaming) in context")
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.05), in: Capsule())
            }

            ForEach(Array(t.messageUsages.enumerated()), id: \.element.id) { i, msg in
                if i > 0 {
                    Rectangle()
                        .fill(.white.opacity(0.05))
                        .frame(height: 0.5)
                        .padding(.leading, 26)
                }
                messageRow(msg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageRow(_ msg: ContextTracker.MessageUsage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Role dot
            VStack(spacing: 0) {
                Circle()
                    .fill(
                        msg.role == "user"
                            ? .white.opacity(0.4)
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
                                ? .white.opacity(0.25)
                                : LamoTheme.Colors.accent.opacity(0.6)
                        )
                        .textCase(.uppercase)

                    Text("\(msg.charCount) chars")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.18))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.15))
                    Text(ContextTracker.formatTokens(msg.tokenCount))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.18))
                }

                Text(msg.preview.isEmpty ? "—" : msg.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(msg.isInContext ? .white.opacity(0.75) : .white.opacity(0.25))
                    .lineLimit(2)
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
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.04), in: Capsule())
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .medium))
                Text(label)
                    .font(.system(size: 10, design: .monospaced).weight(.medium))
            }
            .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 0.5)
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

    private func ringColor(_ t: ContextTracker) -> Color {
        if t.fillRatio >= 0.9 { return .orange }
        if t.fillRatio >= 0.7 { return LamoTheme.Colors.accent }
        return .white.opacity(0.5)
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
        case .nominal:  return "Cool"
        case .fair:     return "Warm"
        case .serious:  return "Hot"
        case .critical: return "Critical"
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
