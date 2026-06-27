import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedConversationID: UUID?
    @State private var showSidebar = false

    private var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebarView
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
            }

            if let conversation = selectedConversation {
                ChatView(
                    conversation: conversation,
                    modelContext: modelContext,
                    onToggleSidebar: { withAnimation { showSidebar.toggle() } },
                    onNewChat: { createNewChat() }
                )
            } else {
                emptyState
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .onAppear {
            ensureConversationExists()
        }
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    createNewChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(LamoTheme.Spacing.md)

                Button {
                    withAnimation { showSidebar = false }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(LamoTheme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, LamoTheme.Spacing.md)
            }

            Divider()

            List(conversations) { conversation in
                Button {
                    selectedConversationID = conversation.id
                    withAnimation { showSidebar = false }
                } label: {
                    ConversationRow(conversation: conversation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    conversation.id == selectedConversationID
                        ? LamoTheme.Colors.accent.opacity(0.15)
                        : Color.clear
                )
            }
            .listStyle(.sidebar)

            Divider()

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LamoTheme.Spacing.md)
            }
            .buttonStyle(.plain)
        }
        .background(LamoTheme.Colors.secondaryBackground)
    }

    private var emptyState: some View {
        VStack(spacing: LamoTheme.Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(LamoTheme.Colors.textSecondary)
            Text("Lamo")
                .font(.largeTitle.bold())
            Text("Start a new conversation")
                .foregroundStyle(LamoTheme.Colors.textSecondary)
            Button("New Chat") {
                createNewChat()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func ensureConversationExists() {
        if let first = conversations.first {
            selectedConversationID = first.id
        } else {
            createNewChat()
        }
    }

    private func createNewChat() {
        let conversation = Conversation()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedConversationID = conversation.id
    }
}
