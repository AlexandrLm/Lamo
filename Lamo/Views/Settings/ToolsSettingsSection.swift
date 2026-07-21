import SwiftUI

struct ToolsSettingsSection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                headerCard
                ForEach(ToolInfo.all) { tool in
                    ToolCardView(tool: tool)
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
                Text("\(ToolInfo.all.filter { $0.isEnabled() }.count)/\(ToolInfo.all.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LamoTheme.Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }
}

// MARK: - Tool Card View

private struct ToolCardView: View {
    let tool: ToolInfo
    @State private var isExpanded = false
    @State private var isEnabled: Bool

    init(tool: ToolInfo) {
        self.tool = tool
        self._isEnabled = State(initialValue: tool.isEnabled())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Collapsed row ──
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: LamoTheme.Spacing.md) {
                    Image(systemName: tool.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(isEnabled ? tool.color : .white.opacity(0.2))
                        .frame(width: 28)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(tool.displayName)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(isEnabled ? .white : .white.opacity(0.35))

                        Text(tool.headline)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .multilineTextAlignment(.leading)
                            .lineLimit(isExpanded ? nil : 2)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        Toggle("", isOn: $isEnabled)
                            .toggleStyle(.switch)
                            .tint(LamoTheme.Colors.accent)
                            .labelsHidden()
                            .onChange(of: isEnabled) { _, newValue in
                                tool.setEnabled(newValue)
                            }

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.2))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)

            // ── Expanded detail ──
            if isExpanded {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                    CompactDivider()

                    // Capabilities (what it can do)
                    detailSection(title: "Capabilities", icon: "sparkles") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tool.capabilities, id: \.self) { cap in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundStyle(tool.color)
                                    Text(cap)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                            }
                        }
                    }


                    // Example prompts
                    detailSection(title: "Try asking", icon: "text.bubble") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tool.examples, id: \.self) { example in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\"")
                                        .foregroundStyle(.white.opacity(0.15))
                                    Text(example)
                                        .font(.system(.caption2, design: .monospaced).italic())
                                        .foregroundStyle(.white.opacity(0.35))
                                    Text("\"")
                                        .foregroundStyle(.white.opacity(0.15))
                                }
                            }
                        }
                    }

                    // Requirements / notes
                    if let note = tool.requirementsNote {
                        detailSection(title: "Requirements", icon: "info.circle") {
                            Text(note)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.top, LamoTheme.Spacing.sm)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
    }

    private func detailSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                Text(title.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
            content()
        }
    }
}

// MARK: - Tool Parameter Info

struct ToolParamInfo {
    let name: String
    let description: String
}

// MARK: - Tool Info Registry

struct ToolInfo: Identifiable {
    let id: String
    let displayName: String
    let headline: String
    let icon: String
    let color: Color
    let capabilities: [String]
    let parameters: [ToolParamInfo]
    let examples: [String]
    let requirementsNote: String?
    let isEnabled: () -> Bool
    let setEnabled: (Bool) -> Void

    /// All tool definitions in display order.
    static let all: [ToolInfo] = [
        // ── Internet ──
        ToolInfo(
            id: "web_search",
            displayName: "Web Search",
            headline: "Search the internet in real time via multiple search engines. Fetches page content for top results.",
            icon: "globe",
            color: .blue,
            capabilities: [
                "Searches the web using SearXNG, Brave, DuckDuckGo, or Google",
                "Returns titles, snippets, and URLs for each result",
                "Optionally auto-fetches full page content from top 3 results",
                "Supports time-based filtering: day, week, month, year",
                "Falls back between providers automatically on failure",
            ],
            parameters: [
                ToolParamInfo(name: "query", description: "Search query — be specific, use natural language"),
                ToolParamInfo(name: "maxResults", description: "Number of results to return (1–10, default 5)"),
                ToolParamInfo(name: "timeRange", description: "Optional: \"day\", \"week\", \"month\", \"year\""),
            ],
            examples: [
                "What are the latest developments in nuclear fusion?",
                "Find me the best pizza places in Brooklyn with reviews",
                "Search for recent papers about on-device LLM inference",
            ],
            requirementsNote: "Requires internet connection. Falls back to offline-only tools when disconnected.",
            isEnabled: { AppDefaults.toolWebSearch.wrappedValue },
            setEnabled: { AppDefaults.toolWebSearch.wrappedValue = $0 }
        ),

        ToolInfo(
            id: "fetch_url",
            displayName: "Fetch URL",
            headline: "Download and extract readable content from any webpage. Caches results for repeated access.",
            icon: "doc.text.magnifyingglass",
            color: .blue,
            capabilities: [
                "Fetches full webpage content as clean extracted text",
                "Extracts title, description, and content type metadata",
                "Strips ads, navigation, and boilerplate from pages",
                "Caches fetched content in memory for the session",
                "Handles redirects and common HTTP error codes",
            ],
            parameters: [
                ToolParamInfo(name: "url", description: "Full URL to fetch (must start with http:// or https://)"),
            ],
            examples: [
                "Read this article: https://example.com/article",
                "What does the documentation at this URL say?",
                "Fetch the latest release notes from the GitHub page",
            ],
            requirementsNote: "Requires internet connection.",
            isEnabled: { AppDefaults.toolFetchURL.wrappedValue },
            setEnabled: { AppDefaults.toolFetchURL.wrappedValue = $0 }
        ),


        // ── Location & Weather ──
        ToolInfo(
            id: "get_location",
            displayName: "Get Location",
            headline: "Determine your approximate location using GPS or IP geolocation. No sign-up or API key needed.",
            icon: "location.fill",
            color: .green,
            capabilities: [
                "GPS mode: precise coordinates via CoreLocation (requires permission)",
                "IP mode: approximate city-level location via ipapi.co (no permission)",
                "Automatic fallback from GPS to IP when GPS unavailable",
                "Reverse geocoding: translates coordinates to city, region, country",
                "Results cached for 2 minutes to avoid repeated requests",
            ],
            parameters: [
                ToolParamInfo(name: "ipOnly", description: "If true, skips GPS and uses IP-based location only (faster)"),
            ],
            examples: [
                "Where am I right now?",
                "What city am I in?",
                "What are my current GPS coordinates?",
            ],
            requirementsNote: "GPS requires Location permission in Settings > Privacy. IP mode works without any permissions.",
            isEnabled: { AppDefaults.toolGetLocation.wrappedValue },
            setEnabled: { AppDefaults.toolGetLocation.wrappedValue = $0 }
        ),

        ToolInfo(
            id: "weather",
            displayName: "Weather",
            headline: "Real-time weather and multi-day forecast via Open-Meteo. Free, no API key, global coverage.",
            icon: "cloud.sun",
            color: .green,
            capabilities: [
                "Current conditions: temperature, humidity, wind speed, cloud cover",
                "Multi-day forecast with daily highs, lows, and conditions",
                "Automatic city detection from Get Location tool result",
                "Manual city search: \"weather in Tokyo\"",
                "Sunrise/sunset times included in forecast",
            ],
            parameters: [
                ToolParamInfo(name: "city", description: "City name (e.g., \"London\"). Leave empty for auto-detect from your location"),
                ToolParamInfo(name: "days", description: "Forecast days (1–7, default 3)"),
            ],
            examples: [
                "What's the weather like today?",
                "Show me the 5-day forecast for Barcelona",
                "Will it rain in Berlin this weekend?",
            ],
            requirementsNote: "Requires internet connection for weather data. City-to-coordinates lookup uses Open-Meteo geocoding API.",
            isEnabled: { AppDefaults.toolWeather.wrappedValue },
            setEnabled: { AppDefaults.toolWeather.wrappedValue = $0 }
        ),

        // ── Productivity ──
        ToolInfo(
            id: "calendar",
            displayName: "Calendar",
            headline: "Full access to your device calendar. List, search, and create events with natural language.",
            icon: "calendar",
            color: .orange,
            capabilities: [
                "List upcoming events with date range and limit controls",
                "Search events by keyword in title, notes, or location",
                "Create new events with title, notes, location, start/end time",
                "Handles all-day events and multi-hour meetings",
                "Calendar permission requested on first use",
            ],
            parameters: [
                ToolParamInfo(name: "mode", description: "\"list\" (upcoming events), \"create\" (new event), or \"search\" (find by keyword)"),
                ToolParamInfo(name: "title", description: "Event title (required for create mode)"),
                ToolParamInfo(name: "startDate", description: "Start date/time in \"yyyy-MM-dd HH:mm\" format"),
                ToolParamInfo(name: "endDate", description: "End date/time in same format"),
                ToolParamInfo(name: "notes", description: "Optional event notes/description"),
                ToolParamInfo(name: "location", description: "Optional event location"),
                ToolParamInfo(name: "query", description: "Search keyword (for search mode)"),
            ],
            examples: [
                "What's on my calendar for tomorrow?",
                "Create a meeting called \"Design Review\" next Monday 2-3pm",
                "Find all events with \"dentist\" in the title",
            ],
            requirementsNote: "Requires Calendar permission on first use. Uses EventKit for read/write access.",
            isEnabled: { AppDefaults.toolCalendar.wrappedValue },
            setEnabled: { AppDefaults.toolCalendar.wrappedValue = $0 }
        ),
        // ── Memory ──
        ToolInfo(
            id: "update_memory",
            displayName: "Memory",
            headline: "Persistent semantic memory. The model remembers facts about you across conversations — fully on-device.",
            icon: "brain.head.profile",
            color: .teal,
            capabilities: [
                "Saves facts as plain text — each fact is one short sentence",
                "Automatic duplicate detection using semantic similarity (on-device BERT embeddings)",
                "Contradictory old facts are automatically replaced with new ones",
                "Conversation summarization for long context windows",
                "Facts listed with numbers for easy reference and removal",
                "Max 50 facts, ~3000 character limit — oldest/least-used auto-pruned",
            ],
            parameters: [
                ToolParamInfo(name: "mode", description: "\"facts\" (save), \"forget\" (remove by number), \"summary\", or \"include_existing\" (list all)"),
                ToolParamInfo(name: "facts", description: "JSON array of fact strings to save, e.g., [\"User lives in Berlin\", \"User is vegetarian\"]"),
                ToolParamInfo(name: "summary", description: "Brief 2–3 sentence recap of the conversation so far"),
            ],
            examples: [
                "Remember that I live in Berlin and I'm vegetarian",
                "What do you remember about me?",
                "Forget everything about my previous job",
            ],
            requirementsNote: "Controlled by the Memory toggle in General Settings. All facts stored locally in SwiftData — never leaves the device.",
            isEnabled: { MemoryService.shared.isEnabled },
            setEnabled: { AppDefaults.memoryEnabled.wrappedValue = $0; MemoryService.shared.isEnabled = $0 }
        ),
    ]
}
