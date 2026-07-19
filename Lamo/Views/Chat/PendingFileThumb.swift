import SwiftUI

struct PendingFileThumb: View {
    let file: PendingFile
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image(systemName: file.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 4, y: -4)
        }
    }
}
