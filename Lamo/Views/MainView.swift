import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?
    @State private var showSettings = false
    @State private var autoNavigate = false
    @State private var searchText = ""

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Lamo")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                            .foregroundStyle(LamoTheme.Colors.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.medium))
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: conversations.count)
                }
            }
            .searchable(text: $searchText, prompt: "Search chats")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(
                    conversation: conversation,
                    modelContext: modelContext
                )
            }
            .navigationDestination(isPresented: $autoNavigate) {
                if let conversation = selectedConversation {
                    ChatView(
                        conversation: conversation,
                        modelContext: modelContext
                    )
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .tint(LamoTheme.Colors.accent)
            .onAppear {
                if selectedConversation == nil {
                    createNewChat()
                    autoNavigate = true
                }
            }
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(conversation: conversation)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteConversation(conversation)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                    .frame(width: 80, height: 80)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())

                VStack(spacing: 6) {
                    Text("No Conversations")
                        .font(.title3.weight(.semibold))

                    Text("Start a new chat to begin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                createNewChat()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.headline)
                    Text("New Chat")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func createNewChat() {
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedConversation = conversation
    }

    private func deleteConversation(_ conversation: Conversation) {
        modelContext.delete(conversation)
        try? modelContext.save()
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: 44, height: 44)

                Image(systemName: "bubble.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(conversation.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(lastMessageSnippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if messageCount > 0 {
                        Text("\(messageCount)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray3))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var lastMessageSnippet: String {
        if let lastMessage = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
            if lastMessage.content.isEmpty {
                return conversation.messages.count > 1 ? "..." : "No messages yet"
            }
            return lastMessage.content
        }
        return "No messages yet"
    }

    private var messageCount: Int {
        conversation.messages.count
    }
}
