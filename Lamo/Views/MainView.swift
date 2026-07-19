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
    @ObservedObject private var providerManager = ProviderManager.shared
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
                            .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
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
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Chat")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    // MARK: - Section Header

    private func sidebarSectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            if title == "Pinned" {
                Circle()
                    .fill(LamoTheme.Colors.accent.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 6)
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
            Spacer().frame(height: 20)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                LamoTheme.Colors.accent.opacity(0.15),
                                LamoTheme.Colors.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
            }

            VStack(spacing: 6) {
                Text("No Chats Yet")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.5))

                Text("Press ⌘N or tap + to start")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.15))

            Text("No Results")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.3))

            Text("Try a different search")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.15))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            LamoTheme.Colors.accent.opacity(0.12),
                                            LamoTheme.Colors.accent.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)

                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.45))
                        }

                        Text("Select a Chat")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))

                        Text("Choose a conversation from the list\nor start a new one with ⌘N")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.25))
                            .multilineTextAlignment(.center)
                    }
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

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var formattedTime: String {
        Self.timeFormatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    private var messageCount: Int {
        conversation.messages.count
    }

    var body: some View {
        HStack(spacing: 0) {
            // Selection accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(LamoTheme.Colors.accent)
                .frame(width: isSelected ? 3 : 0)
                .opacity(isSelected ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
                    }
                    Text(conversation.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.85))

                    Spacer(minLength: 8)

                    Text(formattedTime)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(isSelected ? 0.25 : 0.18))
                        .lineLimit(1)

                    if messageCount > 1 {
                        Text("\(messageCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.07 : 0.0))
                .animation(.easeOut(duration: 0.2), value: isSelected)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("\(conversation.title), \(formattedTime)\(messageCount > 1 ? ", \(messageCount) messages" : "")")
    }
}
