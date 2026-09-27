import SwiftUI

struct ToolsSettingsSection: View {
    @State private var refreshTick = 0

    var body: some View {
        ScrollView {
            LazyVStack(spacing: LamoTheme.Spacing.md) {
                headerCard
                ForEach(ToolCategory.allCases) { category in
                    let tools = ToolInfo.all.filter { $0.category == category }
                    if !tools.isEmpty {
                        categoryBlock(category, tools: tools)
                    }
                }
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.xxxl)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Tools")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func categoryBlock(_ category: ToolCategory, tools: [ToolInfo]) -> some View {
        // Читаем refreshTick, чтобы счётчики обновлялись без .id() —
        // .id() пересоздавал весь список и сбрасывал скролл наверх.
        _ = refreshTick
        return VStack(alignment: .leading, spacing: LamoTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text(category.title.uppercased())
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                Spacer()
                Text("\(tools.filter { $0.isEnabled() }.count)/\(tools.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textGhost)
            }
            .padding(.horizontal, 4)

            ForEach(tools) { tool in
                ToolCardView(tool: tool) { refreshTick += 1 }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        // Читаем refreshTick, чтобы счётчик обновлялся после тогглов.
        _ = refreshTick
        return HStack(spacing: LamoTheme.Spacing.sm) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 14))
                .foregroundStyle(LamoTheme.Colors.textMedium)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(ToolInfo.all.filter { $0.isEnabled() }.count) of \(ToolInfo.all.count) on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Text("AI calls them itself when needed")
                    .font(.caption2)
                    .foregroundStyle(LamoTheme.Colors.textFaint)
            }
            Spacer()
            Button(allOn ? "Turn all off" : "Turn all on") {
                setAll(!allOn)
                refreshTick += 1
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(LamoTheme.Colors.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LamoTheme.Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    private var allOn: Bool {
        ToolInfo.all.allSatisfy { $0.isEnabled() }
    }

    private func setAll(_ on: Bool) {
        for tool in ToolInfo.all { tool.setEnabled(on) }
    }
}

// MARK: - Tool Card View

private struct ToolCardView: View {
    let tool: ToolInfo
    var onToggle: () -> Void = {}
    @State private var isExpanded = false
    @State private var isEnabled: Bool

    init(tool: ToolInfo, onToggle: @escaping () -> Void = {}) {
        self.tool = tool
        self.onToggle = onToggle
        self._isEnabled = State(initialValue: tool.isEnabled())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Collapsed row ──
            HStack(alignment: .center, spacing: LamoTheme.Spacing.sm) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: LamoTheme.Spacing.md) {
                        ToolBadge(icon: tool.icon, tint: tool.color, size: 32)
                            .saturation(isEnabled ? 1 : 0)
                            .opacity(isEnabled ? 1 : 0.5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isEnabled ? LamoTheme.Colors.textHigh : LamoTheme.Colors.textLow)

                            Text(tool.headline)
                                .font(.caption)
                                .foregroundStyle(LamoTheme.Colors.textLow)
                                .multilineTextAlignment(.leading)
                                .lineLimit(isExpanded ? nil : 2)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LamoTheme.Colors.textGhost)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .tint(LamoTheme.Colors.accent)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, newValue in
                        tool.setEnabled(newValue)
                        onToggle()
                    }
            }

            // ── Expanded detail ──
            if isExpanded {
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                    CompactDivider()

                    // Capabilities (what it can do)
                    detailSection(title: String(localized: "Capabilities"), icon: "sparkles") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tool.capabilities, id: \.self) { cap in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundStyle(tool.color)
                                    Text(cap)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(LamoTheme.Colors.textLow)
                                }
                            }
                        }
                    }

                    // Example prompts
                    detailSection(title: String(localized: "Try asking"), icon: "text.bubble") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(tool.examples, id: \.self) { example in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\"")
                                        .foregroundStyle(LamoTheme.Colors.textGhost)
                                    Text(example)
                                        .font(.system(.caption2, design: .monospaced).italic())
                                        .foregroundStyle(LamoTheme.Colors.textLow)
                                    Text("\"")
                                        .foregroundStyle(LamoTheme.Colors.textGhost)
                                }
                            }
                        }
                    }

                    // Parameters (what the AI can pass)
                    if !tool.parameters.isEmpty {
                        detailSection(title: String(localized: "Parameters"), icon: "slider.horizontal.3") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(tool.parameters, id: \.name) { param in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(param.name)
                                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                            .foregroundStyle(LamoTheme.Colors.textMedium)
                                        Text(param.description)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(LamoTheme.Colors.textLow)
                                    }
                                }
                            }
                        }
                    }

                    // Requirements / notes
                    if let note = tool.requirementsNote {
                        detailSection(title: String(localized: "Requirements"), icon: "info.circle") {
                            Text(note)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(LamoTheme.Colors.textFaint)
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
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                Text(title.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textFaint)
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

enum ToolCategory: String, CaseIterable, Identifiable {
    case internet = "Internet"
    case location = "Location"
    case productivity = "Productivity"
    case memory = "Memory"

    var id: String { rawValue }
    var title: String { rawValue }
}

struct ToolInfo: Identifiable {
    let id: String
    let displayName: String
    let headline: String
    let icon: String
    let color: Color
    let category: ToolCategory
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
            id: ToolDefinitions.WebSearch.name,
            displayName: String(localized: "Web Search"),
            headline: String(localized: "Search the internet in real time via multiple search engines. Fetches page content for top results."),
            icon: "globe",
            color: toolColor(name: "web_search"),
            category: .internet,
            capabilities: [
                String(localized: "Searches the web using SearXNG, Brave, DuckDuckGo, or Google"),
                String(localized: "Returns titles, snippets, and URLs for each result"),
                String(localized: "Optionally auto-fetches full page content from top 3 results"),
                String(localized: "Supports time-based filtering: day, week, month, year"),
                String(localized: "Falls back between providers automatically on failure"),
            ],
            parameters: [
                ToolParamInfo(name: "query", description: String(localized: "Search query — be specific, use natural language")),
                ToolParamInfo(name: "maxResults", description: String(localized: "Number of results to return (1–10, default 5)")),
                ToolParamInfo(name: "timeRange", description: String(localized: "Optional: \"day\", \"week\", \"month\", \"year\"")),
            ],
            examples: [
                String(localized: "What are the latest developments in nuclear fusion?"),
                String(localized: "Find me the best pizza places in Brooklyn with reviews"),
                String(localized: "Search for recent papers about on-device LLM inference"),
            ],
            requirementsNote: String(localized: "Requires internet connection. Falls back to offline-only tools when disconnected."),
            isEnabled: { AppDefaults.toolWebSearch.wrappedValue },
            setEnabled: { AppDefaults.toolWebSearch.wrappedValue = $0 }
        ),

        ToolInfo(
            id: ToolDefinitions.FetchURL.name,
            displayName: String(localized: "Fetch URL"),
            headline: String(localized: "Download and extract readable content from any webpage. Caches results for repeated access."),
            icon: "doc.text.magnifyingglass",
            color: toolColor(name: "fetch_url"),
            category: .internet,
            capabilities: [
                String(localized: "Fetches full webpage content as clean extracted text"),
                String(localized: "Extracts title, description, and content type metadata"),
                String(localized: "Strips ads, navigation, and boilerplate from pages"),
                String(localized: "Caches fetched content in memory for the session"),
                String(localized: "Handles redirects and common HTTP error codes"),
            ],
            parameters: [
                ToolParamInfo(name: "url", description: String(localized: "Full URL to fetch (must start with http:// or https://)")),
            ],
            examples: [
                String(localized: "Read this article: https://example.com/article"),
                String(localized: "What does the documentation at this URL say?"),
                String(localized: "Fetch the latest release notes from the GitHub page"),
            ],
            requirementsNote: String(localized: "Requires internet connection."),
            isEnabled: { AppDefaults.toolFetchURL.wrappedValue },
            setEnabled: { AppDefaults.toolFetchURL.wrappedValue = $0 }
        ),

        // ── Location & Weather ──
        ToolInfo(
            id: ToolDefinitions.GetLocation.name,
            displayName: String(localized: "Get Location"),
            headline: String(localized: "Determine your approximate location using GPS or IP geolocation. No sign-up or API key needed."),
            icon: "location.fill",
            color: toolColor(name: "get_location"),
            category: .location,
            capabilities: [
                String(localized: "GPS mode: precise coordinates via CoreLocation (requires permission)"),
                String(localized: "IP mode: approximate city-level location via ipapi.co (no permission)"),
                String(localized: "Automatic fallback from GPS to IP when GPS unavailable"),
                String(localized: "Reverse geocoding: translates coordinates to city, region, country"),
                String(localized: "Results cached for 2 minutes to avoid repeated requests"),
            ],
            parameters: [
                ToolParamInfo(name: "ipOnly", description: String(localized: "If true, skips GPS and uses IP-based location only (faster)")),
            ],
            examples: [
                String(localized: "Where am I right now?"),
                String(localized: "What city am I in?"),
                String(localized: "What are my current GPS coordinates?"),
            ],
            requirementsNote: String(localized: "GPS requires Location permission in Settings > Privacy. IP mode works without any permissions."),
            isEnabled: { AppDefaults.toolGetLocation.wrappedValue },
            setEnabled: { AppDefaults.toolGetLocation.wrappedValue = $0 }
        ),

        ToolInfo(
            id: ToolDefinitions.Weather.name,
            displayName: String(localized: "Weather"),
            headline: String(localized: "Real-time weather and multi-day forecast via Open-Meteo. Free, no API key, global coverage."),
            icon: "cloud.sun",
            color: toolColor(name: "weather"),
            category: .location,
            capabilities: [
                String(localized: "Current conditions: temperature, humidity, wind speed, cloud cover"),
                String(localized: "Multi-day forecast with daily highs, lows, and conditions"),
                String(localized: "Automatic city detection from Get Location tool result"),
                String(localized: "Manual city search: \"weather in Tokyo\""),
                String(localized: "Sunrise/sunset times included in forecast"),
            ],
            parameters: [
                ToolParamInfo(name: "city", description: String(localized: "City name (e.g., \"London\"). Leave empty for auto-detect from your location")),
                ToolParamInfo(name: "days", description: String(localized: "Forecast days (1–7, default 3)")),
            ],
            examples: [
                String(localized: "What's the weather like today?"),
                String(localized: "Show me the 5-day forecast for Barcelona"),
                String(localized: "Will it rain in Berlin this weekend?"),
            ],
            requirementsNote: String(localized: "Requires internet connection for weather data. City-to-coordinates lookup uses Open-Meteo geocoding API."),
            isEnabled: { AppDefaults.toolWeather.wrappedValue },
            setEnabled: { AppDefaults.toolWeather.wrappedValue = $0 }
        ),

        // ── Productivity ──
        ToolInfo(
            id: ToolDefinitions.Calendar.name,
            displayName: String(localized: "Calendar"),
            headline: String(localized: "Full access to your device calendar. List, search, and create events with natural language."),
            icon: "calendar",
            color: toolColor(name: "calendar"),
            category: .productivity,
            capabilities: [
                String(localized: "List upcoming events with date range and limit controls"),
                String(localized: "Search events by keyword in title, notes, or location"),
                String(localized: "Create new events with title, notes, location, start/end time"),
                String(localized: "Handles all-day events and multi-hour meetings"),
                String(localized: "Calendar permission requested on first use"),
            ],
            parameters: [
                ToolParamInfo(name: "mode", description: String(localized: "\"list\" (upcoming events), \"create\" (new event), or \"search\" (find by keyword)")),
                ToolParamInfo(name: "title", description: String(localized: "Event title (required for create mode)")),
                ToolParamInfo(name: "startDate", description: String(localized: "Start date/time in \"yyyy-MM-dd HH:mm\" format")),
                ToolParamInfo(name: "endDate", description: String(localized: "End date/time in same format")),
                ToolParamInfo(name: "notes", description: String(localized: "Optional event notes/description")),
                ToolParamInfo(name: "location", description: String(localized: "Optional event location")),
                ToolParamInfo(name: "query", description: String(localized: "Search keyword (for search mode)")),
            ],
            examples: [
                String(localized: "What's on my calendar for tomorrow?"),
                String(localized: "Create a meeting called \"Design Review\" next Monday 2-3pm"),
                String(localized: "Find all events with \"dentist\" in the title"),
            ],
            requirementsNote: String(localized: "Requires Calendar permission on first use. Uses EventKit for read/write access."),
            isEnabled: { AppDefaults.toolCalendar.wrappedValue },
            setEnabled: { AppDefaults.toolCalendar.wrappedValue = $0 }
        ),
        // ── Memory ──
        ToolInfo(
            id: ToolDefinitions.UpdateMemory.name,
            displayName: String(localized: "Memory"),
            headline: String(localized: "Persistent semantic memory. The model remembers facts about you across conversations — fully on-device."),
            icon: "brain.head.profile",
            color: toolColor(name: "update_memory"),
            category: .memory,
            capabilities: [
                String(localized: "Saves facts as plain text — each fact is one short sentence"),
                String(localized: "Automatic duplicate detection using semantic similarity (on-device BERT embeddings)"),
                String(localized: "Contradictory old facts are automatically replaced with new ones"),
                String(localized: "Conversation summarization for long context windows"),
                String(localized: "Facts listed with numbers for easy reference and removal"),
                String(localized: "Max 50 facts, ~3000 character limit — oldest/least-used auto-pruned"),
            ],
            parameters: [
                ToolParamInfo(name: "mode", description: String(localized: "\"facts\" (save), \"forget\" (remove by number), \"summary\", or \"include_existing\" (list all)")),
                ToolParamInfo(name: "facts", description: String(localized: "JSON array of fact strings to save, e.g., [\"User lives in Berlin\", \"User is vegetarian\"]")),
                ToolParamInfo(name: "summary", description: String(localized: "Brief 2–3 sentence recap of the conversation so far")),
            ],
            examples: [
                String(localized: "Remember that I live in Berlin and I'm vegetarian"),
                String(localized: "What do you remember about me?"),
                String(localized: "Forget everything about my previous job"),
            ],
            requirementsNote: String(localized: "Controlled by the Memory toggle in General Settings. All facts stored locally in SwiftData — never leaves the device."),
            isEnabled: { MemoryService.shared.isEnabled },
            setEnabled: { AppDefaults.memoryEnabled.wrappedValue = $0; MemoryService.shared.isEnabled = $0 }
        ),
    ]
}
