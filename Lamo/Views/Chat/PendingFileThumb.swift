import SwiftUI

struct PendingFileThumb: View, Equatable {
    let file: PendingFile
    let onRemove: () -> Void

    static func == (lhs: PendingFileThumb, rhs: PendingFileThumb) -> Bool {
        lhs.file == rhs.file
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Image(systemName: file.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 220, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            ThumbRemoveButton(size: 18, action: onRemove)
                .offset(x: 4, y: -4)
        }
    }
}
