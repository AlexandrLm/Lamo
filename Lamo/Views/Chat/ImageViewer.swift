import SwiftUI
import UIKit

/// Full-screen image viewer with pinch-to-zoom and swipe-to-dismiss.
struct ImageViewer: View {
    let images: [UIImage]
    let startIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var currentIndex: Int

    init(images: [UIImage], startIndex: Int = 0) {
        self.images = images
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(images.indices, id: \.self) { index in
                    ZoomableImage(
                        image: images[index],
                        scale: $scale,
                        lastScale: $lastScale,
                        offset: $offset,
                        lastOffset: $lastOffset
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .onChange(of: currentIndex) {
                // Reset zoom when swiping to a different image
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .padding(.top, 60)
            .padding(.trailing, 16)

            if images.count > 1 {
                VStack {
                    Spacer()
                    Text("\(currentIndex + 1) / \(images.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Zoomable Image (per-page zoom with limits)

private struct ZoomableImage: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize

    private let maxScale: CGFloat = 5.0

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnification)
            .gesture(pan)
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                    lastScale = 1.0
                }
            }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(lastScale * value.magnification, maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3)) {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                    lastScale = 1.0
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1.0 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
}
