import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversation: Conversation?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
                }
            }
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(
                    conversation: conversation,
                    modelContext: modelContext
                )
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .onAppear {
                ensureConversationExists()
            }
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(conversations) { conversation in
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
        VStack(spacing: LamoTheme.Spacing.xxl) {
            Spacer()

            VStack(spacing: LamoTheme.Spacing.md) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(LamoTheme.Colors.textTertiary)

                VStack(spacing: LamoTheme.Spacing.sm) {
                    Text("Lamo")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(LamoTheme.Colors.textPrimary)

                    Text("Local AI Assistant")
                        .font(LamoTheme.Fonts.subheadline)
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
            }

            Spacer()

            Button {
                createNewChat()
            } label: {
                HStack {
                    Image(systemName: "plus")
                        .font(.headline)
                    Text("New Chat")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LamoTheme.Colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.input, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, LamoTheme.Spacing.xl)
            .padding(.bottom, LamoTheme.Spacing.xl)
        }
    }

    // MARK: - Actions

    private func ensureConversationExists() {
        // Don't auto-create — let the user start fresh
    }

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
