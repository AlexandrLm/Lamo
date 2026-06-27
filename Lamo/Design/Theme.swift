import SwiftUI

enum LamoTheme {
    enum Colors {
        // Backgrounds
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)

        // Accent — 使用 iOS 系统蓝色作为主色调
        static let accent = Color.accentColor
        static let accentGradient = LinearGradient(
            colors: [Color.blue, Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Bubbles
        static let userBubble = Color.accentColor
        static let assistantBubble = Color(uiColor: .secondarySystemBackground)
        static let bubbleTextUser = Color.white
        static let bubbleTextAssistant = Color.primary

        // Text
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(uiColor: .tertiaryLabel)

        // Semantic
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

        // Glass effects (iOS 27 Liquid Glass)
        static let glassBackground = Color.white.opacity(0.06)
        static let glassStroke = Color.white.opacity(0.12)
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
        static let input: CGFloat = 22
        static let card: CGFloat = 16
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
}

// MARK: - Glass Effect Modifier (iOS 27 Liquid Glass)

struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat = LamoTheme.CornerRadius.card
    var opacity: Double = 0.06

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(opacity), lineWidth: 0.5)
            )
    }
}

extension View {
    func glassEffect(cornerRadius: CGFloat = LamoTheme.CornerRadius.card, opacity: Double = 0.06) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: phase - 0.3),
                            .init(color: .white.opacity(0.15), location: phase),
                            .init(color: .clear, location: phase + 0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.overlay)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: LamoTheme.CornerRadius.card, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 8

        var path = Path()

        if isUser {
            // User bubble — tail on bottom-right
            path.addRoundedRect(
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailSize, height: rect.height - tailSize),
                cornerSize: CGSize(width: radius, height: radius)
            )
        } else {
            // Assistant bubble — tail on bottom-left
            path.addRoundedRect(
                in: CGRect(x: rect.minX + tailSize, y: rect.minY, width: rect.width - tailSize, height: rect.height - tailSize),
                cornerSize: CGSize(width: radius, height: radius)
            )
        }

        return path
    }
}
