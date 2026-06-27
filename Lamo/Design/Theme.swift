import SwiftUI

enum LamoTheme {
    enum Colors {
        // Backgrounds
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)

        // Accent — deep indigo-violet (Apple Intelligence style)
        static let accent = Color(red: 0.35, green: 0.35, blue: 1.0)
        static let accentGradient = LinearGradient(
            colors: [Color(red: 0.35, green: 0.35, blue: 1.0), Color.purple.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Bubbles
        static let userBubble = Color(red: 0.35, green: 0.35, blue: 1.0)
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
        static let roundedCaption = Font.system(.caption, design: .rounded).weight(.medium)
        static let roundedHeadline = Font.system(.headline, design: .rounded).weight(.semibold)
        static let code = Font.system(.subheadline, design: .monospaced)
        static let codeBlock = Font.system(.callout, design: .monospaced)
    }
}

// MARK: - Glass Effect Modifier (iOS 27 Liquid Glass)

struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat = LamoTheme.CornerRadius.card

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.4), .clear],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
    }
}

extension View {
    func glassEffect(cornerRadius: CGFloat = LamoTheme.CornerRadius.card) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius))
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

        var path = Path()

        if isUser {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        } else {
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: radius, height: radius),
                style: .continuous
            )
        }

        return path
    }
}

struct AsymmetricRoundedShape: Shape {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: topLeft, height: topLeft),
            style: .continuous
        )
        return path
    }
}
