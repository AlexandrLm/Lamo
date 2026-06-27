import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: LamoTheme.Spacing.md) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    LabeledContent("Version", value: "1.0")
                }
                HStack(spacing: LamoTheme.Spacing.md) {
                    Image(systemName: "cpu")
                        .foregroundStyle(.purple)
                        .font(.title3)
                    LabeledContent("LLM Provider", value: "Apple Intelligence (Local)")
                }
            } header: {
                Text("About")
            } footer: {
                Text("Lamo uses local device models to process your data privately and securely.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
