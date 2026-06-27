import SwiftUI

enum LamoTheme {
    enum Colors {
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let userBubble = Color.accentColor
        static let assistantBubble = Color(uiColor: .secondarySystemBackground)
        static let accent = Color.accentColor
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let bubbleTextUser = Color.white
        static let bubbleTextAssistant = Color.primary
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum CornerRadius {
        static let bubble: CGFloat = 18
        static let input: CGFloat = 22
    }

    enum Fonts {
        static let body = Font.body
        static let headline = Font.headline.weight(.semibold)
        static let subheadline = Font.subheadline
        static let caption = Font.caption
        static let code = Font.system(.subheadline, design: .monospaced)
    }
}
