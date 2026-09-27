import SwiftUI

// MARK: - Glass Card

/// Applies the app's standard Liquid-Glass card surface.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = LamoTheme.CornerRadius.md
    var interactive: Bool = false

    func body(content: Content) -> some View {
        content.glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = LamoTheme.CornerRadius.md, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }
}

// MARK: - Badge

/// Tiny uppercase status capsule (e.g. "ACTIVE", "ON-DEVICE").
struct Badge: View, Equatable {
    let text: String
    var tint: Color = LamoTheme.Colors.accent
    var foreground: Color = .black

    // Color isn't Equatable — identity is the text (tint/foreground are static styling).
    static func == (lhs: Badge, rhs: Badge) -> Bool { lhs.text == rhs.text }

    var body: some View {
        Text(text)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint)
            .clipShape(Capsule())
    }
}

// MARK: - Chip

/// Tinted pill with optional icon — the shared spec/value/metadata chip.
struct Chip: View, Equatable {
    let text: String
    var icon: String?
    var tint: Color = LamoTheme.Colors.accent
    var textColor: Color = LamoTheme.Colors.textHigh
    var font: Font = .system(size: 9, design: .monospaced)

    // Color/Font aren't Equatable — identity is text+icon (styling is static per call site).
    static func == (lhs: Chip, rhs: Chip) -> Bool {
        lhs.text == rhs.text && lhs.icon == rhs.icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(tint.opacity(0.6))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(font)
        .foregroundStyle(textColor.opacity(0.8))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(tint.opacity(0.08)))
    }
}

// MARK: - Section Header

/// Uppercase monospaced section title with optional accent icon.
struct SectionHeader: View {
    let title: String
    var icon: String?
    var tint: Color = LamoTheme.Colors.accent

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(tint.opacity(0.8))
                .tracking(1)
        }
    }
}

// MARK: - Icon Badge

/// Circular icon on a tinted circle — fetch/search/html/memory result badges.
struct IconBadge: View {
    let icon: String
    var tint: Color = LamoTheme.Colors.accent
    var size: CGFloat = 34
    var iconScale: CGFloat = 0.4

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * iconScale, weight: .semibold))
                .foregroundStyle(tint.opacity(0.7))
        }
    }
}

// MARK: - Tool Badge

/// Rounded-square icon tile for tools — one shared style for chat cards and settings.
struct ToolBadge: View {
    let icon: String
    var tint: Color = LamoTheme.Colors.accent
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(tint.opacity(0.13))
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 0.75)
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Pressable Scale Button Style

/// Subtle press-down feedback for custom buttons (plain style gives none).
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.95

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Thumb Remove Button

/// Shared "remove attachment" button (palette xmark over a translucent disc).
struct ThumbRemoveButton: View {
    var size: CGFloat = 20
    var overlay: Color = LamoTheme.Colors.fillOverlay
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: size))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, overlay)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meter Bar

/// Progress track — unifies battery/storage/download bars.
/// No GeometryReader: fill is a full-width capsule scaled by the clamped ratio,
/// so N rows cost one layout pass with a fixed height instead of N measurements.
struct MeterBar: View, Equatable {
    /// 0...1 fill ratio.
    let value: Double
    var tint: Color = LamoTheme.Colors.accent
    var height: CGFloat = 6
    var track: Color = LamoTheme.Colors.fillMedium

    private var clamped: Double { min(max(value, 0), 1) }

    // Color isn't Equatable — identity is value+height.
    static func == (lhs: MeterBar, rhs: MeterBar) -> Bool {
        lhs.value == rhs.value && lhs.height == rhs.height
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(track)
                .frame(height: height)
            Capsule()
                .fill(tint)
                .frame(height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: clamped, anchor: .leading)
        }
        .frame(height: height)
    }
}

// MARK: - Row Action Button

/// Compact icon button for message action rows — replaces 44×44 tap targets.
struct RowActionButton: View {
    let icon: String
    var label: String = ""
    var color: Color = LamoTheme.Colors.textFaint
    var size: CGFloat = 28
    var iconSize: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.isEmpty ? icon : label)
    }
}

// MARK: - Code Preview Block

/// Expandable monospaced content block — unifies "PAGE CONTENT"/output previews.
/// Stores a truncated preview up front; the full text is only rendered after
/// the user taps "Show more" (lazy fullText), so long tool outputs don't
/// inflate the layout pass while collapsed or previewed.
struct CodePreviewBlock: View, Equatable {
    let title: String
    let text: String
    var tint: Color = LamoTheme.Colors.accent
    @State private var isExpanded = false
    @State private var showFull = false

    /// Chars shown before "Show more" appears.
    static let previewLimit = 800

    private var preview: String {
        text.count > Self.previewLimit ? String(text.prefix(Self.previewLimit)) + "…" : text
    }

    private var isTruncated: Bool { text.count > Self.previewLimit }

    // Color isn't Equatable — identity is title+text.
    static func == (lhs: CodePreviewBlock, rhs: CodePreviewBlock) -> Bool {
        lhs.title == rhs.title && lhs.text == rhs.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 8))
                    Text(title)
                        .font(.system(size: 8, design: .monospaced))
                    Spacer()
                }
                .foregroundStyle(tint.opacity(0.45))
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(showFull ? text : preview)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textLow)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isTruncated {
                        Button(showFull ? String(localized: "Show less") : String(localized: "Show more")) {
                            withAnimation(.easeInOut(duration: 0.2)) { showFull.toggle() }
                        }
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.7))
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(LamoTheme.Colors.fillSubtle, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(LamoTheme.Colors.fillStrong.opacity(0.6), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
