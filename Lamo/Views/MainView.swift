import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedID: UUID?
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var hasAppeared = false
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @StateObject private var providerManager = ProviderManager.shared

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedID }
    }

    private var groupedConversations: [(title: String, items: [Conversation])] {
        let cal = Calendar.current
        let now = Date()
        let unpinned = filteredConversations.filter { !$0.isPinned }

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var lastWeek: [Conversation] = []
        var older: [Conversation] = []

        for conv in unpinned {
            let updated = conv.updatedAt
            if cal.isDateInToday(updated) {
                today.append(conv)
            } else if cal.isDateInYesterday(updated) {
                yesterday.append(conv)
            } else if updated > cal.date(byAdding: .day, value: -7, to: now)! {
                lastWeek.append(conv)
            } else {
                older.append(conv)
            }
        }

        var groups: [(String, [Conversation])] = []

        let pinned = filteredConversations.filter { $0.isPinned }
        if !pinned.isEmpty {
            groups.append(("Pinned", pinned))
        }
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !lastWeek.isEmpty { groups.append(("Previous 7 Days", lastWeek)) }
        if !older.isEmpty { groups.append(("Older", older)) }
        return groups
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .tint(LamoTheme.Colors.accent)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Rename Chat", isPresented: .init(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField("Chat name", text: $renameText)
            Button("Rename") {
                guard let id = renamingID,
                      let conv = conversations.first(where: { $0.id == id }) else { return }
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                conv.title = trimmed.isEmpty ? "New Chat" : trimmed
                try? modelContext.save()
                renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                resetLeftoverStreamingState()
                cleanupEmptyConversations()
                startNewChat()
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedID) {
            if filteredConversations.isEmpty && !searchText.isEmpty {
                ContentUnavailableView("No Chats Found", systemImage: "magnifyingglass")
                    .listRowSeparator(.hidden)
            } else if filteredConversations.isEmpty {
                ContentUnavailableView("Start a Conversation", systemImage: "bubble.left", description: Text("Your chats will appear here"))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(groupedConversations, id: \.title) { group in
                    Section {
                        ForEach(group.items) { conversation in
                            ConversationRow(conversation: conversation)
                                .tag(conversation.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete")
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        togglePin(conversation)
                                    } label: {
                                        Label(
                                            conversation.isPinned ? "Unpin" : "Pin",
                                            systemImage: conversation.isPinned ? "pin.slash" : "pin"
                                        )
                                    }
                                    .tint(conversation.isPinned ? .gray : .orange)
                                }
                                .contextMenu {
                                    Button {
                                        renamingID = conversation.id
                                        renameText = conversation.title
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Button {
                                        togglePin(conversation)
                                    } label: {
                                        Label(
                                            conversation.isPinned ? "Unpin" : "Pin",
                                            systemImage: conversation.isPinned ? "pin.slash" : "pin"
                                        )
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete")
                                }
                        }
                    } header: {
                        HStack(spacing: 5) {
                            if group.title == "Pinned" {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                            }
                            Text(group.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
        .searchable(text: $searchText, prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Settings")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .accessibilityLabel("New Chat")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Detail

    private var detailContent: some View {
        ZStack {
            Group {
                if let conversation = selectedConversation {
                    ChatView(
                        conversation: conversation,
                        modelContext: modelContext,
                        onNewChat: {
                            startNewChat()
                        }
                    )
                } else {
                    ContentUnavailableView("Select a Chat", systemImage: "bubble.left", description: Text("Choose a conversation or start a new one"))
                }
            }

            // Startup gate: show loading overlay until engine is ready
            if !providerManager.isEngineReady {
                ZStack {
                    LamoTheme.Colors.background.ignoresSafeArea()

                    VStack(spacing: 0) {
                        Spacer()

                        VStack(spacing: LamoTheme.Spacing.lg) {
                            if let error = providerManager.engineError {
                                // Error state
                                VStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text("Engine Error")
                                        .font(.system(.body, design: .monospaced).weight(.medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                    Text(error)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(4)
                                }
                                .padding(LamoTheme.Spacing.xl)
                                .frame(maxWidth: 320)
                                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                            } else {
                                // Loading state
                                LoadingView(modelName: providerManager.currentModelDisplayName)
                            }
                        }

                        Spacer()
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Actions

    private func startNewChat() {
        cleanupEmptyConversations()
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedID = conversation.id
    }

    private func togglePin(_ conversation: Conversation) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        conversation.isPinned.toggle()
        try? modelContext.save()
    }

    private func deleteConversation(_ conversation: Conversation) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        for message in conversation.messages {
            for path in message.imagePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        if selectedID == conversation.id {
            selectedID = nil
        }
        modelContext.delete(conversation)
        try? modelContext.save()
    }

    private func cleanupEmptyConversations() {
        for conv in conversations where conv.messages.isEmpty {
            if selectedID != conv.id {
                modelContext.delete(conv)
            }
        }
        try? modelContext.save()
        
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let oneHourAgo = Date().addingTimeInterval(-3600)
        for file in files where file.lastPathComponent.hasPrefix("img_") && file.pathExtension == "jpg" {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let created = attrs[.creationDate] as? Date,
               created < oneHourAgo {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func resetLeftoverStreamingState() {
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.isStreaming })
        guard let streaming = try? modelContext.fetch(descriptor) else { return }
        for msg in streaming { msg.isStreaming = false }
        try? modelContext.save()
    }
}

// MARK: - Loading View

private struct LoadingView: View {
    let modelName: String
    @State private var phase = 0
    @State private var pulse = false

    private let phases = [
        "Validating model",
        "Mapping memory",
        "Initializing engine",
        "Almost ready"
    ]

    var body: some View {
        VStack(spacing: LamoTheme.Spacing.lg) {
            // Pulsing ring
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 2)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(pulse ? 360 : 0))
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: pulse)
            }

            VStack(spacing: 6) {
                Text(modelName)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)

                Text(phases[phase % phases.count])
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .animation(.easeInOut, value: phase)
            }
        }
        .padding(LamoTheme.Spacing.xl)
        .frame(maxWidth: 320)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
        .onAppear {
            pulse = true
            startPhaseTimer()
        }
    }

    private func startPhaseTimer() {
        Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
            withAnimation { phase += 1 }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    private var firstUserMessage: String? {
        conversation.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .first(where: { $0.role == .user })?.content
    }

    private var lastMessagePreview: String? {
        conversation.messages
            .sorted(by: { $0.timestamp < $1.timestamp })
            .last?.content
    }

    private var previewText: String? {
        if let first = firstUserMessage, !first.isEmpty {
            return String(first.prefix(80))
        }
        return lastMessagePreview.map { String($0.prefix(80)) }
    }

    private var messageCount: Int {
        conversation.messages.count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    )

                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.orange)
                        .clipShape(Circle())
                        .offset(x: 3, y: 3)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let preview = previewText {
                    HStack(spacing: 4) {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        if messageCount > 0 {
                            Text("· \(messageCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(conversation.title), \(relativeTime)")
    }
}
