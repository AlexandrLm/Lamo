import SwiftUI

enum LamoTheme {
    enum Colors {
        // Backgrounds — clean, minimal
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)

        // Accent — clean blue (like Claude/ChatGPT)
        static let accent = Color(red: 0.2, green: 0.4, blue: 0.9)
        static let accentGradient = LinearGradient(
            colors: [Color(red: 0.2, green: 0.4, blue: 0.9), Color(red: 0.3, green: 0.3, blue: 0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Bubbles
        static let userBubble = Color(uiColor: .systemFill)
        static let assistantBubble = Color.clear
        static let bubbleTextUser = Color.primary
        static let bubbleTextAssistant = Color.primary

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(uiColor: .tertiaryLabel)

        // Semantic
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

        // Separators
        static let separator = Color(uiColor: .separator)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let bubble: CGFloat = 16
        static let input: CGFloat = 24
        static let card: CGFloat = 12
    }

    enum Fonts {
        static let largeTitle = Font.largeTitle.bold()
        static let title = Font.title2.bold()
        static let title3 = Font.title3.bold()
        static let headline = Font.headline.weight(.semibold)
        static let body = Font.body
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let code = Font.system(.subheadline, design: .monospaced)
        static let codeBlock = Font.system(.callout, design: .monospaced)
    }

    // Max width for chat content (iPad optimization)
    static let maxContentWidth: CGFloat = 768
}

// MARK: - Bubble Shape (asymmetric for natural feel)

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = LamoTheme.CornerRadius.bubble
        var path = Path()

        if isUser {
            // User: rounded top-left, sharp bottom-left
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        } else {
            // Assistant: rounded corners everywhere
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        }

        return path
    }
}

// MARK: - Separator

struct CompactDivider: View {
    var body: some View {
        Rectangle()
            .fill(LamoTheme.Colors.separator.opacity(0.4))
            .frame(height: 0.5)
    }
}
