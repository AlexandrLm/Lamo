import SwiftUI

enum LamoTheme {
    enum Colors {
        // Backgrounds — native iOS
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)

        // Accent — black & white
        static let accent = Color.primary

        // Bubbles
        static let userBubble = Color(uiColor: .systemGray5)
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
        static let bubble: CGFloat = 18
        static let input: CGFloat = 20
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

    static let maxContentWidth: CGFloat = 768
}

// MARK: - Separator

struct CompactDivider: View {
    var body: some View {
        Rectangle()
            .fill(LamoTheme.Colors.separator.opacity(0.35))
            .frame(height: 0.5)
    }
}
