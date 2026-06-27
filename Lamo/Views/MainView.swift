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
                .id(conversation.id) // Force view refresh on conversation change
            } else {
                emptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            ensureConversationExists()
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: $selectedConversationID) {
            ForEach(conversations) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Lamo")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: LamoTheme.Spacing.sm) {
                // New Chat Button
                Button {
                    createNewChat()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("New Chat")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LamoTheme.Spacing.sm + 2)
                    .glassEffect(cornerRadius: LamoTheme.CornerRadius.lg)
                }
                .buttonStyle(.plain)

                // Settings Button
                NavigationLink {
                    SettingsView()
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
                    .padding(.vertical, LamoTheme.Spacing.xs)
                    .padding(.horizontal, LamoTheme.Spacing.md)
                    .glassEffect(cornerRadius: LamoTheme.CornerRadius.md)
                }
            }
            .padding(LamoTheme.Spacing.md)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: LamoTheme.Spacing.xl) {
            Spacer(minLength: 80)

            // Animated icon
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.variableColor.iterative, isActive: true)

            VStack(spacing: LamoTheme.Spacing.sm) {
                Text("Lamo")
                    .font(LamoTheme.Fonts.largeTitle)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)

                Text("Local AI Assistant")
                    .font(LamoTheme.Fonts.subheadline)
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
            }

            // Quick action cards
            VStack(spacing: LamoTheme.Spacing.md) {
                QuickPromptCard(
                    icon: "brain.head.profile",
                    title: "Start a conversation",
                    subtitle: "Ask anything — all processing stays on your device"
                )
            }
            .padding(.horizontal, LamoTheme.Spacing.xl)

            Spacer()
        }
    }

    // MARK: - Actions

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

// MARK: - Quick Prompt Card

struct QuickPromptCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: LamoTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(LamoTheme.Colors.accent)
                .frame(width: 44, height: 44)
                .background(LamoTheme.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LamoTheme.Fonts.headline)
                    .foregroundStyle(LamoTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(LamoTheme.Fonts.caption)
                    .foregroundStyle(LamoTheme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LamoTheme.Colors.textTertiary)
        }
        .padding(LamoTheme.Spacing.md)
        .glassEffect(cornerRadius: LamoTheme.CornerRadius.card)
    }
}
