import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversationID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    private var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarView
        } detail: {
            if let conversation = selectedConversation {
                ChatView(
                    conversation: conversation,
                    modelContext: modelContext,
                    onNewChat: { createNewChat() }
                )
            } else {
                emptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            ensureConversationExists()
        }
    }

    private var sidebarView: some View {
        List(selection: $selectedConversationID) {
            ForEach(conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    createNewChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(LamoTheme.Colors.accent)
                .clipShape(Capsule())

                Spacer()

                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(LamoTheme.Spacing.md)
            .background(.ultraThinMaterial)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LamoTheme.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
            Text("Lamo")
                .font(.largeTitle.bold())
            Text("Select a chat or start a new conversation")
                .font(LamoTheme.Fonts.subheadline)
                .foregroundStyle(LamoTheme.Colors.textSecondary)
            Button("New Chat") {
                createNewChat()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func ensureConversationExists() {
        if selectedConversationID == nil {
            if let first = conversations.first {
                selectedConversationID = first.id
            } else {
                createNewChat()
            }
        }
    }

    private func createNewChat() {
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedConversationID = conversation.id
    }

    private func deleteConversation(_ conversation: Conversation) {
        let isDeletedSelected = selectedConversationID == conversation.id
        modelContext.delete(conversation)
        try? modelContext.save()
        if isDeletedSelected {
            selectedConversationID = conversations.first?.id
        }
    }
}
