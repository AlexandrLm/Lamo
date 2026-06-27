import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ConversationListViewModel?
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Start a new chat to begin")
                    } actions: {
                        Button {
                            _ = viewModel?.createConversation()
                        } label: {
                            Label("New Chat", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(conversations) { conversation in
                            NavigationLink(value: conversation) {
                                ConversationRow(conversation: conversation)
                            }
                        }
                        .onDelete { indexSet in
                            viewModel?.deleteConversations(indexSet, from: conversations)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Lamo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        _ = viewModel?.createConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.medium))
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: conversations.count)
                }
            }
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation, modelContext: modelContext)
            }
            .onAppear {
                if viewModel == nil {
                    viewModel = ConversationListViewModel(modelContext: modelContext)
                }
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textPrimary)
                .lineLimit(1)

            Text(lastMessageSnippet)
                .font(.subheadline)
                .foregroundStyle(LamoTheme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var lastMessageSnippet: String {
        if let lastMessage = conversation.messages.sorted(by: { $0.timestamp < $1.timestamp }).last {
            return lastMessage.content.isEmpty ? "..." : lastMessage.content
        }
        return "No messages yet"
    }
}
