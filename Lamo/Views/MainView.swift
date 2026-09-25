import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @State private var selectedID: UUID?
    @State private var hasAppeared = false

    private var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                conversations: conversations,
                selectedID: $selectedID,
                onNewChat: startNewChat,
                onDelete: deleteConversation,
                onTogglePin: togglePin
            )
        } detail: {
            detailContent
        }
        .tint(LamoTheme.Colors.accent)
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                resetLeftoverStreamingState()
                cleanupEmptyConversations()
                startNewChat()
            }
        }
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
                            .foregroundStyle(LamoTheme.Colors.textMedium)

                        Text("Choose a conversation from the list\nor start a new one with ⌘N")
                            .font(.subheadline)
                            .foregroundStyle(LamoTheme.Colors.textFaint)
                            .multilineTextAlignment(.center)
                    }
                }
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
