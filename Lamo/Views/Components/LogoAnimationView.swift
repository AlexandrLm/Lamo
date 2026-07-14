import SwiftUI

/// Animated logo inspired by the Lamo app icon — ethereal glowing layers
/// that breathe, rotate, and shift like translucent glass planes.
struct LogoAnimationView: View {
    var size: CGFloat = 120

    @State private var phase: CGFloat = 0
    @State private var isVisible = false

    private let layerCount = 5
    private let animationDuration: Double = 8.0

    var body: some View {
        ZStack {
            // Central glow
            centralGlow

            // Translucent rotating layers
            ForEach(0..<layerCount, id: \.self) { i in
                layer(at: i)
            }

            // Outer squircle border
            squircleBorder
        }
        .frame(width: size, height: size)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 1.2)) {
                isVisible = true
            }
            withAnimation(
                .linear(duration: animationDuration)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    // MARK: - Central Glow

    private var centralGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        .white.opacity(0.5),
                        .white.opacity(0.15),
                        .white.opacity(0.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.25
                )
            )
            .frame(width: size * 0.5, height: size * 0.5)
            .blur(radius: size * 0.08)
            .scaleEffect(isVisible ? 1.0 : 0.5)
            .animation(
                .easeInOut(duration: 3.0)
                .repeatForever(autoreverses: true)
                .delay(0.5),
                value: isVisible
            )
    }

    // MARK: - Translucent Layers

    private func layer(at index: Int) -> some View {
        let progress = phase
        let offset = Double(index) / Double(layerCount)
        let rotation = progress * 360 + offset * 72
        let scale = 0.4 + offset * 0.55
        let opacity = 0.08 + (1.0 - offset) * 0.18

        return RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(opacity),
                        .white.opacity(opacity * 0.3),
                        .white.opacity(opacity * 0.8),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.0
            )
            .frame(
                width: size * scale,
                height: size * scale * 0.85
            )
            .rotationEffect(.degrees(rotation + Double(index) * 30))
            .blur(radius: 1.5)
            .blendMode(.screen)
            .animation(
                .linear(duration: animationDuration)
                .repeatForever(autoreverses: false)
                .delay(Double(index) * 0.3),
                value: phase
            )
    }

    // MARK: - Squircle Border

    private var squircleBorder: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .stroke(
                AngularGradient(
                    colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.25),
                        .white.opacity(0.0),
                        .white.opacity(0.15),
                        .white.opacity(0.0),
                    ],
                    center: .center
                ),
                lineWidth: 1.0
            )
            .frame(width: size * 0.92, height: size * 0.92)
            .rotationEffect(.degrees(phase * 120))
            .animation(
                .linear(duration: animationDuration * 1.5)
                .repeatForever(autoreverses: false),
                value: phase
            )
    }
}

#Preview {
    ZStack {
        Color.black
        LogoAnimationView(size: 200)
    }
}
