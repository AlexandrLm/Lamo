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

        ToolInfo(
            id: "wikipedia",
            displayName: "Wikipedia",
            headline: "Search Wikipedia or extract full articles. Auto-detects language based on your query.",
            icon: "book.closed",
            color: .blue,
            capabilities: [
                "Search mode: find articles by keyword, returns titles + snippets",
                "Extract mode: get full article text with page metadata",
                "Disambiguation detection — suggests more specific titles",
                "Language auto-detection and manual language selection",
                "Handles redirects and normalized titles",
            ],
            parameters: [
                ToolParamInfo(name: "query", description: "Article title for extract mode, keywords for search mode"),
                ToolParamInfo(name: "mode", description: "\"search\" (list articles) or \"extract\" (full article text)"),
                ToolParamInfo(name: "language", description: "Wikipedia language code — \"en\", \"ru\", \"de\", etc."),
                ToolParamInfo(name: "maxResults", description: "Max search results (1–10, default 5)"),
            ],
            examples: [
                "Search Wikipedia for quantum computing",
                "Show me the full Wikipedia article about Paris",
                "What does Russian Wikipedia say about Baikonur?",
            ],
            requirementsNote: "Requires internet connection.",
            isEnabled: { AppDefaults.toolWikipedia.wrappedValue },
            setEnabled: { AppDefaults.toolWikipedia.wrappedValue = $0 }
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

        ToolInfo(
            id: "calendar_availability",
            displayName: "Calendar Availability",
            headline: "Find free time slots in your schedule. Perfect for scheduling meetings without back-and-forth.",
            icon: "calendar.badge.clock",
            color: .orange,
            capabilities: [
                "Scans your calendar for gaps between events",
                "Customizable slot duration, working hours, and search range",
                "Returns date, start/end time, and duration for each free slot",
                "Configurable maximum number of slots to return",
                "Respects your working hours (e.g., 9:00–18:00)",
            ],
            parameters: [
                ToolParamInfo(name: "durationMinutes", description: "Minimum slot duration in minutes (default 60)"),
                ToolParamInfo(name: "startDate", description: "Search range start in YYYY-MM-DD format (default: today)"),
                ToolParamInfo(name: "endDate", description: "Search range end (default: today + 7 days)"),
                ToolParamInfo(name: "workHoursStart", description: "Working hours start, 0–23 (default 9)"),
                ToolParamInfo(name: "workHoursEnd", description: "Working hours end, 0–23 (default 18)"),
                ToolParamInfo(name: "maxSlots", description: "Maximum number of slots to return (default 10)"),
            ],
            examples: [
                "When am I free for a 30-minute call this week?",
                "Find 2-hour blocks on Friday afternoon",
                "Show me available slots next Monday between 10am and 4pm",
            ],
            requirementsNote: "Requires Calendar permission. Uses EventKit for read-only schedule access.",
            isEnabled: { AppDefaults.toolCalendarAvailability.wrappedValue },
            setEnabled: { AppDefaults.toolCalendarAvailability.wrappedValue = $0 }
        ),

        ToolInfo(
            id: "contacts",
            displayName: "Contacts",
            headline: "Search your device contacts by name, phone, email, or organization. Results stay on-device.",
            icon: "person.crop.circle",
            color: .orange,
            capabilities: [
                "Full-text search across contact names and organizations",
                "Retrieves phone numbers, emails, and organization info",
                "Multiple results returned ranked by match relevance",
                "No data leaves the device — all processing is local",
                "Uses Apple's Contacts framework with permission prompt",
            ],
            parameters: [
                ToolParamInfo(name: "query", description: "Name, phone number, email, or organization to search for"),
            ],
            examples: [
                "What's John's phone number?",
                "Find contacts at Apple Inc.",
                "Search for anyone with \"doctor\" in their name",
            ],
            requirementsNote: "Requires Contacts permission on first use. Data never leaves your device.",
            isEnabled: { AppDefaults.toolContacts.wrappedValue },
            setEnabled: { AppDefaults.toolContacts.wrappedValue = $0 }
        ),

        ToolInfo(
            id: "notes",
            displayName: "Notes",
            headline: "Manage personal notes stored on device. Create, read, search, and delete notes as plain text.",
            icon: "note.text",
            color: .orange,
            capabilities: [
                "List all notes with titles, content previews, and timestamps",
                "Search notes by keyword — matches title and content",
                "Create new notes with title and body text",
                "Read full content of any note by title",
                "Delete notes by exact title",
            ],
            parameters: [
                ToolParamInfo(name: "mode", description: "\"list\", \"search\", \"read\", \"create\", or \"delete\""),
                ToolParamInfo(name: "title", description: "Note title (required for read, create, delete modes)"),
                ToolParamInfo(name: "query", description: "Search keyword (required for search mode)"),
                ToolParamInfo(name: "content", description: "Note body text (required for create mode)"),
            ],
            examples: [
                "Show me all my notes",
                "Create a note called \"Shopping List\" with milk and eggs",
                "Search my notes for anything about travel",
            ],
            requirementsNote: "Notes stored locally in app sandbox. No cloud sync — fully private.",
            isEnabled: { AppDefaults.toolNotes.wrappedValue },
            setEnabled: { AppDefaults.toolNotes.wrappedValue = $0 }
        ),

        // ── Health & System ──
        ToolInfo(
            id: "health",
            displayName: "Health",
            headline: "Read your Apple Health data: steps, heart rate, sleep analysis, weight, and activity summary.",
            icon: "heart.fill",
            color: .red,
            capabilities: [
                "Steps: daily counts with per-day breakdown over any range (1–30 days)",
                "Heart rate: min, avg, max BPM with 10 most recent readings",
                "Sleep: per-night duration, average, and daily breakdown",
                "Weight: most recent measurement with timestamp",
                "Summary: combined overview of all metrics at once",
            ],
            parameters: [
                ToolParamInfo(name: "mode", description: "\"steps\", \"heart_rate\", \"sleep\", \"weight\", or \"summary\""),
                ToolParamInfo(name: "days", description: "How many days to look back (1–30, default 1)"),
            ],
            examples: [
                "How many steps did I take yesterday?",
                "What's my average heart rate this week?",
                "Show me my sleep data for the past 3 days",
                "Give me a health summary",
            ],
            requirementsNote: "Requires Health permission. Uses HealthKit — all data stays on device. Sleep data requires Apple Watch or sleep tracking app.",
            isEnabled: { AppDefaults.toolHealth.wrappedValue },
            setEnabled: { AppDefaults.toolHealth.wrappedValue = $0 }
        ),

        ToolInfo(
            id: "shortcuts",
            displayName: "Shortcuts",
            headline: "Run Siri Shortcuts to control HomeKit devices, send messages, or trigger any automation.",
            icon: "bolt.fill",
            color: .yellow,
            capabilities: [
                "Execute any Siri Shortcut by name from your library",
                "Passes input text to the shortcut for parameterized actions",
                "Returns shortcut output as text for the model to describe",
                "Can control HomeKit, send messages, create reminders, etc.",
                "No additional permissions — uses existing Shortcuts permissions",
            ],
            parameters: [
                ToolParamInfo(name: "name", description: "Exact name of the shortcut to run (case-insensitive)"),
                ToolParamInfo(name: "input", description: "Optional text input passed to the shortcut"),
            ],
            examples: [
                "Run my \"Good Morning\" shortcut",
                "Turn off the living room lights using shortcuts",
                "Execute my \"Send ETA\" shortcut with input \"running 5 min late\"",
            ],
            requirementsNote: "Shortcuts must exist in your Shortcuts app. Some shortcuts may require additional permissions configured in the Shortcuts app.",
            isEnabled: { AppDefaults.toolShortcuts.wrappedValue },
            setEnabled: { AppDefaults.toolShortcuts.wrappedValue = $0 }
        ),

        // ── Compute & Analysis ──
        ToolInfo(
            id: "calculator",
            displayName: "Calculator",
            headline: "Evaluate mathematical expressions safely. Supports arithmetic, trigonometry, logarithms, and more.",
            icon: "function",
            color: .purple,
            capabilities: [
                "Basic arithmetic: +, -, *, /, %, ** (power), ! (factorial)",
                "Trigonometry: sin, cos, tan, asin, acos, atan",
                "Logarithms: log (base 10), log2, ln (natural log)",
                "Rounding: round, floor, ceil, abs",
                "Constants: pi, e (Euler's number)",
                "Scientific notation: 1.5e10, 2.5e-3",
                "Percentage expressions: \"200 * 15%\"",
                "Factorials up to 20! (integer only)",
            ],
            parameters: [
                ToolParamInfo(name: "expression", description: "Math expression — uses standard notation with *, /, +, -, **, etc."),
            ],
            examples: [
                "What is 15% of 245? → 245 * 15%",
                "Calculate sqrt((3^2 + 4^2))",
                "What is 100 * sin(45°) + log(1000)?",
            ],
            requirementsNote: "Fully offline — no internet needed. Evaluation uses NSExpression with safe function substitution.",
            isEnabled: { AppDefaults.toolCalculator.wrappedValue },
            setEnabled: { AppDefaults.toolCalculator.wrappedValue = $0 }
        ),

        ToolInfo(
            id: "code_sandbox",
            displayName: "Code Sandbox",
            headline: "Execute JavaScript in an isolated sandbox. Use for calculations, data processing, and text manipulation.",
            icon: "curlybraces",
            color: .purple,
            capabilities: [
                "Full JavaScript execution via JavaScriptCore engine",
                "Sandboxed — no file system, network, or system access",
                "5-second timeout prevents infinite loops",
                "Capture output via \"result\" variable or expression return value",
                "Error messages include exception details for debugging",
            ],
            parameters: [
                ToolParamInfo(name: "code", description: "JavaScript code to execute. Use `result` variable to return output."),
            ],
            examples: [
                "Sort this list alphabetically: [\"zebra\", \"apple\", \"monkey\"]",
                "Calculate the median of [12, 5, 8, 19, 3, 15]",
                "Convert this JSON to a formatted table",
            ],
            requirementsNote: "Runs locally in JavaScriptCore. No network access. Code is sandboxed and cannot access device data.",
            isEnabled: { AppDefaults.toolCodeSandbox.wrappedValue },
            setEnabled: { AppDefaults.toolCodeSandbox.wrappedValue = $0 }
        ),

        // ── Memory & Planning ──
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

        ToolInfo(
            id: "create_plan",
            displayName: "Planner",
            headline: "Create multi-step plans for complex tasks. The model declares steps up front, then executes them in order.",
            icon: "list.bullet.clipboard",
            color: .teal,
            capabilities: [
                "Declarative planning: model outlines all steps before executing",
                "Visual progress tracking in the chat UI",
                "Each step specifies which tool to call and what it should do",
                "Plan progress persists across tool calls — model knows what's done",
                "Failed steps don't block the plan — model can adapt",
            ],
            parameters: [
                ToolParamInfo(name: "goal", description: "Short description of the overall goal, e.g., \"Plan a weekend trip to SPb\""),
                ToolParamInfo(name: "steps", description: "JSON array: [{\"tool\":\"weather\",\"description\":\"Check weekend forecast\"}, {\"tool\":\"calendar\",\"description\":\"Find free slots\"}]"),
            ],
            examples: [
                "Plan a trip to Paris this weekend — check weather, flights, and hotels",
                "Help me prepare for a job interview: research the company, find my resume, check calendar",
                "Create a plan to learn Swift: find resources, set up Xcode, write first app",
            ],
            requirementsNote: "Meta-tool — orchestrates other tools. Steps auto-advance when each tool completes.",
            isEnabled: { AppDefaults.toolPlanner.wrappedValue },
            setEnabled: { AppDefaults.toolPlanner.wrappedValue = $0 }
        ),
    ]
}
