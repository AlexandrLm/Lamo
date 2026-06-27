import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedID: UUID?
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var hasAppeared = false

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
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                startNewChat()
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedID) {
            Button {
                startNewChat()
            } label: {
                Label {
                    Text("New Chat")
                        .font(.body)
                } icon: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
            }
            .listRowBackground(Color(.tertiarySystemFill))

            Section {
                ForEach(filteredConversations) { conversation in
                    ConversationRow(conversation: conversation)
                        .tag(conversation.id)
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
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("Select or start a new chat")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func startNewChat() {
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedID = conversation.id
    }

    private func deleteConversation(_ conversation: Conversation) {
        modelContext.delete(conversation)
        try? modelContext.save()
        if selectedID == conversation.id {
            selectedID = nil
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.body)
                .lineLimit(1)
        }
    }
}
