import SwiftUI

struct TypingIndicator: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ProgressView()
                .tint(LamoTheme.Colors.accent)

            Spacer(minLength: 48)
        }
    }
}
