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
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a new chat")
                    )
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
                }
            }
            .navigationTitle("Lamo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        _ = viewModel?.createConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
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

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: LamoTheme.Spacing.xs) {
            Text(conversation.title)
                .font(LamoTheme.Fonts.headline)
                .lineLimit(1)

            Text(conversation.updatedAt, style: .relative)
                .font(LamoTheme.Fonts.caption)
                .foregroundStyle(LamoTheme.Colors.textSecondary)
        }
        .padding(.vertical, LamoTheme.Spacing.xs)
    }
}
