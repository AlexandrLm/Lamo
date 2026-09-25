import SwiftData
import SwiftUI

/// Sidebar: search, grouped chat list, settings entry, rename/delete flows.
/// Grouping is a plain computed value — no manual cache, so pin/rename
/// re-layout the list immediately (a stale cache used to miss those).
struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selectedID: UUID?
    var onNewChat: () -> Void = {}
    var onDelete: (Conversation) -> Void = { _ in }
    var onTogglePin: (Conversation) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var conversationToRename: Conversation?
    @State private var renameText = ""
    @State private var conversationToDelete: Conversation?

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private struct Group: Identifiable {
        let title: String
        let items: [Conversation]
        var id: String { title }
    }

    private var groupedConversations: [Group] {
        let cal = Calendar.current
        let now = Date()
        let unpinned = filteredConversations.filter { !$0.isPinned }

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var lastWeek: [Conversation] = []
        var older: [Conversation] = []

        for conv in unpinned {
            let updated = conv.updatedAt
            if cal.isDateInToday(updated) {
                today.append(conv)
            } else if cal.isDateInYesterday(updated) {
                yesterday.append(conv)
            } else if let weekAgo = cal.date(byAdding: .day, value: -7, to: now), updated > weekAgo {
                lastWeek.append(conv)
            } else {
                older.append(conv)
            }
        }

        var groups: [Group] = []
        let pinned = filteredConversations.filter { $0.isPinned }
        if !pinned.isEmpty { groups.append(Group(title: String(localized: "Pinned"), items: pinned)) }
        if !today.isEmpty { groups.append(Group(title: String(localized: "Today"), items: today)) }
        if !yesterday.isEmpty { groups.append(Group(title: String(localized: "Yesterday"), items: yesterday)) }
        if !lastWeek.isEmpty { groups.append(Group(title: String(localized: "Previous 7 Days"), items: lastWeek)) }
        if !older.isEmpty { groups.append(Group(title: String(localized: "Older"), items: older)) }
        return groups
    }

    var body: some View {
        List(selection: $selectedID) {
            if filteredConversations.isEmpty && !searchText.isEmpty {
                emptySearchView
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if filteredConversations.isEmpty {
                emptyStateView
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groupedConversations) { group in
                    Section {
                        ForEach(group.items) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: selectedID == conversation.id,
                                onRename: { beginRename(conversation) },
                                onTogglePin: { onTogglePin(conversation) },
                                onDelete: { conversationToDelete = conversation }
                            )
                            .tag(conversation.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button {
                                    beginRename(conversation)
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button {
                                    onTogglePin(conversation)
                                } label: {
                                    Label(
                                        conversation.isPinned ? "Unpin" : "Pin",
                                        systemImage: conversation.isPinned ? "pin.slash" : "pin"
                                    )
                                }

                                Divider()

                                Button(role: .destructive) {
                                    conversationToDelete = conversation
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityLabel("Delete")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    conversationToDelete = conversation
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityLabel("Delete")
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    onTogglePin(conversation)
                                } label: {
                                    Label(
                                        conversation.isPinned ? "Unpin" : "Pin",
                                        systemImage: conversation.isPinned ? "pin.slash" : "pin"
                                    )
                                }
                                .tint(conversation.isPinned ? .gray : .orange)
                            }
                        }
                    } header: {
                        sidebarSectionHeader(group.title, count: group.items.count)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selectedID)
        .background {
            sidebarAmbientGradient
        }
        .navigationTitle("Chats")
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        .searchable(text: $searchText, prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LamoTheme.Colors.textMedium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New Chat")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Rename Chat", item: $conversationToRename) { conversation in
            TextField("Chat name", text: $renameText)
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                conversation.title = trimmed.isEmpty ? String(localized: "New Chat") : trimmed
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Chat?", item: $conversationToDelete) { conversation in
            Button("Delete", role: .destructive) {
                onDelete(conversation)
            }
            Button("Cancel", role: .cancel) {}
        } message: { conversation in
            Text("Delete \"\(conversation.title)\" and all its messages?")
        }
    }

    // MARK: - Rename

    private func beginRename(_ conversation: Conversation) {
        renameText = conversation.title
        conversationToRename = conversation
    }

    // MARK: - Section Header

    private func sidebarSectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            if title == String(localized: "Pinned") {
                Circle()
                    .fill(LamoTheme.Colors.accent.opacity(0.5))
                    .frame(width: 5, height: 5)
            }
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(LamoTheme.Colors.textFaint)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textGhost)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Ambient Gradient

    private var sidebarAmbientGradient: some View {
        // Hue matched to the teal accent (0.48) so the sidebar and chat feel connected.
        // Adaptive: dark → deep glow on black; light → soft pastel tint on white.
        LinearGradient(
            stops: [
                .init(color: Color(uiColor: UIColor { tc in
                    if tc.userInterfaceStyle == .dark {
                        return UIColor(hue: 0.48, saturation: 0.12, brightness: 0.10, alpha: 1)
                    } else {
                        return UIColor(hue: 0.48, saturation: 0.10, brightness: 0.93, alpha: 1)
                    }
                }), location: 0),
                .init(color: .clear, location: 0.45)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 20)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                LamoTheme.Colors.accent.opacity(0.15),
                                LamoTheme.Colors.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(LamoTheme.Colors.accent.opacity(0.5))
            }

            VStack(spacing: 6) {
                Text("No Chats Yet")
                    .font(.headline)
                    .foregroundStyle(LamoTheme.Colors.textMedium)

                Text("Press ⌘N or tap + to start")
                    .font(.subheadline)
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 40)
    }

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(LamoTheme.Colors.textGhost)

            Text("No Results")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LamoTheme.Colors.textFaint)

            Text("Try a different search")
                .font(.caption)
                .foregroundStyle(LamoTheme.Colors.textGhost)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    var isSelected: Bool = false
    var onRename: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var isHovering = false

    /// Today → exact time; yesterday → "Yesterday"; older → calendar date.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var formattedTime: String {
        let cal = Calendar.current
        if cal.isDateInToday(conversation.updatedAt) {
            return Self.timeFormatter.string(from: conversation.updatedAt)
        }
        if cal.isDateInYesterday(conversation.updatedAt) {
            return String(localized: "Yesterday")
        }
        return Self.dateFormatter.string(from: conversation.updatedAt)
    }

    private var messageCount: Int {
        conversation.messages.count
    }

    /// One-line preview of the newest message. Reuses the already-faulted
    /// messages collection (messageCount above pays the fault), so ~free.
    private var lastMessagePreview: String? {
        let msgs = conversation.messages
        guard !msgs.isEmpty else { return nil }
        guard let last = msgs.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        let text = last.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if !text.isEmpty {
            let prefix = last.role == .user ? String(localized: "You: ") : ""
            return prefix + String(text.prefix(80))
        }
        if last.hasImages { return String(localized: "Photo") }
        if last.hasAttachedFiles { return last.attachedFileNames.first ?? String(localized: "Attachment") }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            // Selected edge bar — the single selection signal.
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LamoTheme.Colors.accent)
                    .frame(width: 3, height: 34)
                    .transition(.opacity)
            }

            avatarView

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(LamoTheme.Colors.textHigh)

                if let preview = lastMessagePreview {
                    Text(preview)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }

            Spacer(minLength: 6)

            trailingSlot
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel("\(conversation.title), \(formattedTime)\(messageCount > 1 ? ", \(messageCount) messages" : "")")
    }

    // Нативный selection-хайлайт List даёт заливку сам — свой фон
    // у выбранного не рисуем, иначе будет двойная подсветка.
    // Сигналы выбора: кромка + полужирный заголовок поверх системной.
    private var rowBackground: Color {
        if isHovering { return LamoTheme.Colors.fillSubtle }
        return .clear
    }

    private var avatarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LamoTheme.Colors.accent.opacity(conversation.isPinned ? 0.45 : 0.26),
                            LamoTheme.Colors.accent.opacity(conversation.isPinned ? 0.18 : 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 34, height: 34)

            Image(systemName: conversation.isPinned ? "pin.fill" : "bubble.left.and.bubble.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LamoTheme.Colors.accent.opacity(0.9))
        }
    }

    /// Trailing column: time over count normally, hover actions on hover.
    private var trailingSlot: some View {
        ZStack(alignment: .trailing) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedTime)
                    .font(.system(size: 10, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(LamoTheme.Colors.textFaint)
                    .lineLimit(1)

                if messageCount > 1 {
                    Text("\(messageCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textFaint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(LamoTheme.Colors.fillMedium))
                } else {
                    // Keeps the title baseline stable whether the badge shows or not.
                    Spacer(minLength: 16)
                }
            }
            .opacity(isHovering ? 0 : 1)

            if isHovering {
                HStack(spacing: 2) {
                    RowActionButton(
                        icon: "pencil",
                        label: String(localized: "Rename"),
                        color: LamoTheme.Colors.textLow,
                        size: 24,
                        iconSize: 11,
                        action: onRename
                    )
                    RowActionButton(
                        icon: conversation.isPinned ? "pin.slash" : "pin",
                        label: conversation.isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                        color: conversation.isPinned ? LamoTheme.Colors.accent : LamoTheme.Colors.textLow,
                        size: 24,
                        iconSize: 11,
                        action: onTogglePin
                    )
                    RowActionButton(
                        icon: "trash",
                        label: String(localized: "Delete"),
                        color: LamoTheme.Colors.error.opacity(0.85),
                        size: 24,
                        iconSize: 11,
                        action: onDelete
                    )
                }
            }
        }
    }
}
