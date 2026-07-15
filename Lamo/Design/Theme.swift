import SwiftUI

enum LamoTheme {
    enum Colors {
        static let background = Color.black
        static let secondaryBackground = Color.black
        static let tertiaryBackground = Color.black

        static let accent = Color(red: 0.06, green: 0.64, blue: 0.50)

        static let userBubble = Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1.0)  // #383838
                : UIColor.systemGray5
        })
        static let assistantBubble = Color.clear
        static let bubbleTextUser = Color.primary
        static let bubbleTextAssistant = Color.primary

        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(uiColor: .tertiaryLabel)

        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

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
