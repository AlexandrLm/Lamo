import SwiftUI

enum LamoTheme {
    enum Colors {
        /// App background — pure adaptive system background (black in dark, white in light).
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.11, alpha: 1)   // #1C1C1C
                : UIColor.systemGray6
        })
        static let tertiaryBackground = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 0.15, alpha: 1)   // #262626
                : UIColor.systemGray5
        })

        /// Brand teal — brighter in dark for glow on black, darker in light for
        /// WCAG contrast on white.
        static let accent = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1.0)
                : UIColor(red: 0.02, green: 0.52, blue: 0.41, alpha: 1.0)
        })

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

        static let success = Color(uiColor: .systemGreen)
        static let warning = Color(uiColor: .systemOrange)
        static let error = Color(uiColor: .systemRed)

        static let separator = Color(uiColor: .separator)

        // MARK: Semantic text hierarchy (adaptive — white-based in dark, black-based in light)
        static let textHigh = Color.primary
        static let textMedium = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.65)
                : UIColor(white: 0.0, alpha: 0.65)
        })
        static let textLow = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.40)
                : UIColor(white: 0.0, alpha: 0.40)
        })
        static let textFaint = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.25)
                : UIColor(white: 0.0, alpha: 0.25)
        })
        static let textGhost = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.15)
                : UIColor(white: 0.0, alpha: 0.15)
        })

        // MARK: Semantic fill hierarchy (adaptive — white overlays in dark, black overlays in light)
        static let fillSubtle = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.04)
                : UIColor(white: 0.0, alpha: 0.05)
        })
        static let fillMedium = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.08)
                : UIColor(white: 0.0, alpha: 0.08)
        })
        static let fillStrong = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 0.0, alpha: 0.12)
        })
        static let fillOverlay = Color.black.opacity(0.55)

        // MARK: Tool identity palette — single source for toolColor(name:).
        // Previously hardcoded as Color(red:...) in ToolCallBlock.swift:225.
        enum Tool {
            static let weather = Color(red: 0.20, green: 0.62, blue: 0.95)
            static let webSearch = Color(red: 0.42, green: 0.48, blue: 0.95)
            static let getLocation = Color(red: 0.95, green: 0.38, blue: 0.42)
            static let fetchURL = Color(red: 0.15, green: 0.65, blue: 0.55)
            static let calendar = Color(red: 0.95, green: 0.55, blue: 0.20)
            static let memory = Color(red: 0.62, green: 0.45, blue: 0.90)
            static let fallback = Color(red: 0.55, green: 0.58, blue: 0.62)
        }

        static func toolColor(name: String) -> Color {
            switch name {
            case "weather": Tool.weather
            case "web_search": Tool.webSearch
            case "get_location": Tool.getLocation
            case "fetch_url": Tool.fetchURL
            case "calendar": Tool.calendar
            case "update_memory", "think": Tool.memory
            default: Tool.fallback
            }
        }

        // MARK: Domain avatar palette — single source for SearchToolBlock domainColor.
        static let domainPalette: [Color] = [
            Color(red: 0.25, green: 0.60, blue: 0.95),
            Color(red: 0.90, green: 0.35, blue: 0.35),
            Color(red: 0.30, green: 0.70, blue: 0.50),
            Color(red: 0.85, green: 0.55, blue: 0.20),
            Color(red: 0.55, green: 0.40, blue: 0.90),
            Color(red: 0.90, green: 0.30, blue: 0.60),
            Color(red: 0.20, green: 0.70, blue: 0.70),
            Color(red: 0.70, green: 0.50, blue: 0.30),
        ]

        static func domainColor(_ domain: String) -> Color {
            var hash = 0
            for byte in domain.utf8 { hash = hash &* 31 &+ Int(byte) }
            return domainPalette[abs(hash) % domainPalette.count]
        }

        /// Warm amber for thinking indicator — bright in dark, deeper in light.
        /// Previously hardcoded in MessageBubble.swift:359.
        static let thinkingAmber = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.94, green: 0.63, blue: 0.19, alpha: 1.0)
                : UIColor(red: 0.72, green: 0.44, blue: 0.08, alpha: 1.0)
        })

        /// Secondary orb tint for empty-chat ambient gradient.
        /// Previously hardcoded in ChatView.swift:367.
        static let chatOrbBlue = Color(red: 0.35, green: 0.55, blue: 0.90)
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

        /// Monospaced font at an arbitrary point size — replaces ad-hoc `.system(...design:.monospaced)`.
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// Rounded font at an arbitrary point size — replaces ad-hoc `.system(...design:.rounded)`.
        static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }

    static let maxContentWidth: CGFloat = 768
}

// MARK: - Separator

/// Unified hairline divider — replaces the many ad-hoc `.white.opacity(0.03–0.06)` copies.
struct ThinDivider: View {
    var body: some View {
        Rectangle()
            .fill(LamoTheme.Colors.separator.opacity(0.35))
            .frame(height: 0.5)
    }
}

/// Backwards-compatible alias.
typealias CompactDivider = ThinDivider

/// Shared byte formatter — ByteCountFormatter init is expensive, never alloc per row.
extension LamoTheme {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f
    }()
}
