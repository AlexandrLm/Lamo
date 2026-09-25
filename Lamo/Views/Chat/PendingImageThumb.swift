import SwiftUI

struct PendingImageThumb: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(LamoTheme.Colors.fillStrong, lineWidth: 0.5)
                )

            ThumbRemoveButton(size: 20, action: onRemove)
                .offset(x: 5, y: -5)
        }
    }
}
