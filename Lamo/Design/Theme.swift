import SwiftUI

enum LamoTheme {
    enum Colors {
        static let background = Color.clear
        static let secondaryBackground = Color.gray.opacity(0.1)
        static let userBubble = Color.blue
        static let assistantBubble = Color.gray.opacity(0.12)
        static let accent = Color.accentColor
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum CornerRadius {
        static let bubble: CGFloat = 16
        static let input: CGFloat = 20
    }

    enum Fonts {
        static let body = Font.body
        static let headline = Font.headline
        static let caption = Font.caption
        static let code = Font.system(.body, design: .monospaced)
    }
}
