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
    @State private var conversationToDelete: Conversation?
    @StateObject private var providerManager = ProviderManager.shared
    /// Cached filtered + grouped conversations — only recomputed when conversations or search text changes.
    @State private var cachedGroups: [(title: String, items: [Conversation])] = []
    @State private var cachedHasResults: Bool = true

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
        cachedGroups
    }

    private func recomputeGroups() {
        let cal = Calendar.current
        let now = Date()
        let filtered = filteredConversations
        let unpinned = filtered.filter { !$0.isPinned }

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
            } else if let weekAgo = cal.date(byAdding: .day, value: -7, to: now), updated > weekAgo {
                lastWeek.append(conv)
            } else {
                older.append(conv)
            }
        }

        var groups: [(String, [Conversation])] = []

        let pinned = filtered.filter { $0.isPinned }
        if !pinned.isEmpty { groups.append(("Pinned", pinned)) }
        if !today.isEmpty { groups.append(("Today", today)) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        if !lastWeek.isEmpty { groups.append(("Previous 7 Days", lastWeek)) }
        if !older.isEmpty { groups.append(("Older", older)) }

        cachedGroups = groups
        cachedHasResults = !filtered.isEmpty
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
        .alert("Delete Chat?", isPresented: .init(
            get: { conversationToDelete != nil },
            set: { if !$0 { conversationToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let conv = conversationToDelete {
                    deleteConversation(conv)
                }
                conversationToDelete = nil
            }
            Button("Cancel", role: .cancel) { conversationToDelete = nil }
        } message: {
            if let conv = conversationToDelete {
                Text("Delete \"\(conv.title)\" and all its messages?")
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                resetLeftoverStreamingState()
                cleanupEmptyConversations()
                startNewChat()
            }
            recomputeGroups()
        }
        .onChange(of: conversations.count) {
            recomputeGroups()
        }
        .onChange(of: conversations.map(\.updatedAt)) {
            recomputeGroups()
        }
        .onChange(of: searchText) {
            recomputeGroups()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedID) {
            if !cachedHasResults && !searchText.isEmpty {
                emptySearchView
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if !cachedHasResults {
                emptyStateView
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groupedConversations, id: \.title) { group in
                    Section {
                        ForEach(group.items) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: selectedID == conversation.id
                            )
                            .tag(conversation.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .listRowBackground(Color.clear)
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
                                    conversationToDelete = conversation
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityLabel("Delete")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    conversationToDelete = conversation
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
                        }
                    } header: {
                        sidebarSectionHeader(group.title)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .background {
            sidebarAmbientGradient
        }
        .navigationTitle("Chats")
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        .searchable(text: $searchText, prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Chat")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Section Header

    private func sidebarSectionHeader(_ title: String) -> some View {
        HStack(spacing: 5) {
            if title == "Pinned" {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Ambient Gradient

    private var sidebarAmbientGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color(
                    hue: 0.58,
                    saturation: 0.12,
                    brightness: 0.10
                ), location: 0),
                .init(color: .clear, location: 0.45)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            LogoAnimationView(size: 80)

            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.5))

                Text("Your chats will appear here")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 60)
    }

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.12))

            Text("No Chats Found")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
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
                    .id(conversation.id)
                } else {
                    ContentUnavailableView(
                        "Select a Chat",
                        systemImage: "bubble.left",
                        description: Text("Choose a conversation or start a new one")
                    )
                }
            }

            // Startup gate: small loading banner instead of full-screen block
            if !providerManager.isEngineReady {
                VStack {
                    if let error = providerManager.engineError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.white.opacity(0.5))
                            Text(error)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(2)
                            Spacer()
                            Button {
                                Task { await providerManager.initializeEngineIfNeeded() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Retry engine load")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
                        .padding(.horizontal, LamoTheme.Spacing.lg)
                        .padding(.top, 8)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.5))
                            Text(providerManager.currentModelDisplayName)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text("Loading…")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
                        .padding(.horizontal, LamoTheme.Spacing.lg)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
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
            for path in message.attachedFilePaths {
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
    }

    private func resetLeftoverStreamingState() {
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.isStreaming })
        guard let streaming = try? modelContext.fetch(descriptor) else { return }
        for msg in streaming { msg.isStreaming = false }
        try? modelContext.save()
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    var isSelected: Bool = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var relativeTime: String {
        Self.relativeFormatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    private var previewText: String? {
        let sorted = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp })
        if let first = sorted.first(where: { $0.role == .user }),
           !first.content.isEmpty {
            return String(first.content.prefix(80))
        }
        if let last = sorted.last, !last.content.isEmpty {
            return String(last.content.prefix(80))
        }
        return nil
    }

    private var avatarLetter: String {
        let title = conversation.title
        return title.isEmpty ? "?" : String(title.prefix(1)).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Monospace letter avatar
            ZStack {
                Circle()
                    .fill(Color.white.opacity(isSelected ? 0.10 : 0.05))
                    .frame(width: 34, height: 34)

                Text(avatarLetter)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(isSelected ? 0.7 : 0.45))
            }

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    HStack(spacing: 4) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        Text(conversation.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
                    }
                    Spacer(minLength: 8)
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.2))
                        .lineLimit(1)
                }

                if let preview = previewText {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.06 : 0.0))
                .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("\(conversation.title), \(relativeTime)")
    }
}
