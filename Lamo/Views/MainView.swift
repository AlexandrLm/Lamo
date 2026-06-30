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

    // MARK: - Grouped Conversations

    private var groupedConversations: [(title: String, items: [Conversation])] {
        let cal = Calendar.current
        let now = Date()
        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var lastWeek: [Conversation] = []
        var older: [Conversation] = []

        for conv in filteredConversations {
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
            // New Chat Button
            Button {
                startNewChat()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LamoTheme.Colors.accent)
                        .frame(width: 32, height: 32)
                        .background(LamoTheme.Colors.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("New Chat")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)
                }
            }
            .listRowBackground(Color(.tertiarySystemFill))
            .listRowSeparator(.hidden)

            if filteredConversations.isEmpty && !searchText.isEmpty {
                ContentUnavailableView("No Chats Found", systemImage: "magnifyingglass")
                    .listRowSeparator(.hidden)
            } else if filteredConversations.isEmpty {
                ContentUnavailableView("Start a Conversation", systemImage: "bubble.left", description: Text("Your chats will appear here"))
                    .listRowSeparator(.hidden)
            } else {
                // Grouped conversations
                ForEach(groupedConversations, id: \.title) { group in
                    Section {
                        ForEach(group.items) { conversation in
                            ConversationRow(conversation: conversation)
                                .tag(conversation.id)
                                .contextMenu {
                                    Button {
                                        renamingID = conversation.id
                                        renameText = conversation.title
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        deleteConversation(conversation)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(group.title)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
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
                }
            }
        }
    }

    // MARK: - Detail

    private var detailContent: some View {
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
    }

    // MARK: - Actions

    private func startNewChat() {
        cleanupEmptyConversations()
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedID = conversation.id
    }

    private func deleteConversation(_ conversation: Conversation) {
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

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let lastMessage = conversation.messages
                    .sorted(by: { $0.timestamp < $1.timestamp })
                    .last {
                    Text(lastMessage.content)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: "bubble.left.fill")
        }
    }
}
