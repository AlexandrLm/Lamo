import SwiftUI

struct ToolsSettingsSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                // Section header
                headerCard

                // Tools list
                ForEach(ToolInfo.all) { tool in
                    toolCard(tool)
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.xxxl)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack(spacing: LamoTheme.Spacing.sm) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                Text("AVAILABLE TOOLS")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                Spacer()
            }
            Text("Toggle which tools the model can use. Fewer tools = faster inference and less token usage.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LamoTheme.Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Tool Card

    private func toolCard(_ tool: ToolInfo) -> some View {
        ToolCardView(tool: tool)
    }
}

// MARK: - Tool Card View (expandable description)

private struct ToolCardView: View {
    let tool: ToolInfo
    @State private var isExpanded = false
    @State private var isEnabled: Bool

    init(tool: ToolInfo) {
        self.tool = tool
        self._isEnabled = State(initialValue: tool.isEnabled())
    }

    var body: some View {
        HStack(alignment: .top, spacing: LamoTheme.Spacing.md) {
            Image(systemName: tool.icon)
                .font(.system(size: 20))
                .foregroundStyle(isEnabled ? .white.opacity(0.8) : .white.opacity(0.25))
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.displayName)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(isEnabled ? .white : .white.opacity(0.35))

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(tool.description)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.leading)
                            .lineLimit(isExpanded ? nil : 2)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.2))
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .tint(LamoTheme.Colors.accent)
                .labelsHidden()
                .padding(.top, 2)
                .onChange(of: isEnabled) { _, newValue in
                    tool.setEnabled(newValue)
                }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }
}

// MARK: - Tool Info Registry

/// Central registry of all available tools with their metadata and toggle state.
struct ToolInfo: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let icon: String
    let isEnabled: () -> Bool
    let setEnabled: (Bool) -> Void

    /// All tool definitions in display order.
    static let all: [ToolInfo] = [
        ToolInfo(
            id: "web_search",
            displayName: "Web Search",
            description: "Search the internet via SearXNG, Brave, DuckDuckGo, or Google.",
            icon: "globe",
            isEnabled: { AppDefaults.toolWebSearch.wrappedValue },
            setEnabled: { AppDefaults.toolWebSearch.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "fetch_url",
            displayName: "Fetch URL",
            description: "Fetch and read the content of any webpage.",
            icon: "doc.text.magnifyingglass",
            isEnabled: { AppDefaults.toolFetchURL.wrappedValue },
            setEnabled: { AppDefaults.toolFetchURL.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "get_current_time",
            displayName: "Current Time",
            description: "Get the current date, time, timezone, and Unix timestamp.",
            icon: "clock",
            isEnabled: { AppDefaults.toolGetCurrentTime.wrappedValue },
            setEnabled: { AppDefaults.toolGetCurrentTime.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "get_location",
            displayName: "Get Location",
            description: "Get your approximate location (city, country, coordinates) via IP. No GPS permissions needed.",
            icon: "location.fill",
            isEnabled: { AppDefaults.toolGetLocation.wrappedValue },
            setEnabled: { AppDefaults.toolGetLocation.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "calculator",
            displayName: "Calculator",
            description: "Evaluate mathematical expressions safely. Supports +, -, *, /, sqrt, sin, cos, log, etc.",
            icon: "function",
            isEnabled: { AppDefaults.toolCalculator.wrappedValue },
            setEnabled: { AppDefaults.toolCalculator.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "open_url",
            displayName: "Open URL",
            description: "Open a link in the system browser (Safari).",
            icon: "safari",
            isEnabled: { AppDefaults.toolOpenURL.wrappedValue },
            setEnabled: { AppDefaults.toolOpenURL.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "wikipedia",
            displayName: "Wikipedia",
            description: "Search Wikipedia articles and get summaries. Auto-detects language.",
            icon: "book.closed",
            isEnabled: { AppDefaults.toolWikipedia.wrappedValue },
            setEnabled: { AppDefaults.toolWikipedia.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "device_info",
            displayName: "Device Info",
            description: "Get device model, OS version, battery, storage, memory, and uptime.",
            icon: "iphone.gen3",
            isEnabled: { AppDefaults.toolDeviceInfo.wrappedValue },
            setEnabled: { AppDefaults.toolDeviceInfo.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "weather",
            displayName: "Weather",
            description: "Get current weather for any city via Open-Meteo (free, no API key).",
            icon: "cloud.sun",
            isEnabled: { AppDefaults.toolWeather.wrappedValue },
            setEnabled: { AppDefaults.toolWeather.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "create_reminder",
            displayName: "Create Reminder",
            description: "Create a reminder in the system Reminders app with optional due date.",
            icon: "bell.badge",
            isEnabled: { AppDefaults.toolCreateReminder.wrappedValue },
            setEnabled: { AppDefaults.toolCreateReminder.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "think",
            displayName: "Deep Think",
            description: "Lets the model pause and reason through complex problems step by step before answering.",
            icon: "lightbulb",
            isEnabled: { AppDefaults.toolThink.wrappedValue },
            setEnabled: { AppDefaults.toolThink.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "code_sandbox",
            displayName: "Code Sandbox",
            description: "Execute JavaScript code in a secure sandbox for calculations, data analysis, and text processing.",
            icon: "curlybraces",
            isEnabled: { AppDefaults.toolCodeSandbox.wrappedValue },
            setEnabled: { AppDefaults.toolCodeSandbox.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "calendar",
            displayName: "Calendar",
            description: "Read and create calendar events. Check your schedule for any date range.",
            icon: "calendar",
            isEnabled: { AppDefaults.toolCalendar.wrappedValue },
            setEnabled: { AppDefaults.toolCalendar.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "contacts",
            displayName: "Contacts",
            description: "Search your device contacts by name, phone, email, or organization.",
            icon: "person.crop.circle",
            isEnabled: { AppDefaults.toolContacts.wrappedValue },
            setEnabled: { AppDefaults.toolContacts.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "notes",
            displayName: "Notes",
            description: "Manage personal notes stored in Lamo. Create, search, read, and delete notes.",
            icon: "note.text",
            isEnabled: { AppDefaults.toolNotes.wrappedValue },
            setEnabled: { AppDefaults.toolNotes.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "shortcuts",
            displayName: "Shortcuts",
            description: "Run Siri Shortcuts to control HomeKit, send messages, or automate tasks.",
            icon: "bolt.fill",
            isEnabled: { AppDefaults.toolShortcuts.wrappedValue },
            setEnabled: { AppDefaults.toolShortcuts.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "health",
            displayName: "Health",
            description: "Read steps, heart rate, sleep, and weight from Apple Health (stays on device).",
            icon: "heart.fill",
            isEnabled: { AppDefaults.toolHealth.wrappedValue },
            setEnabled: { AppDefaults.toolHealth.wrappedValue = $0 }
        ),
        ToolInfo(
            id: "calendar_availability",
            displayName: "Find Free Slots",
            description: "Find available time slots in your calendar for scheduling meetings or planning.",
            icon: "clock.badge.checkmark",
            isEnabled: { AppDefaults.toolCalendarAvailability.wrappedValue },
            setEnabled: { AppDefaults.toolCalendarAvailability.wrappedValue = $0 }
        ),
    ]
}
