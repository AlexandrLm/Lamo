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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.title)
                    .font(LamoTheme.Fonts.headline)
                    .lineLimit(1)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)

                Spacer()

                Text(conversation.updatedAt, style: .relative)
                    .font(LamoTheme.Fonts.caption)
                    .foregroundStyle(LamoTheme.Colors.textTertiary)
            }

            HStack(spacing: LamoTheme.Spacing.sm) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(LamoTheme.Colors.accent)
                }

                Text(lastMessageSnippet)
                    .font(LamoTheme.Fonts.subheadline)
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
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
