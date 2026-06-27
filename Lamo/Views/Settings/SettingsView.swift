import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    LabeledContent("LLM Provider", value: "Apple Intelligence (Local)")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
