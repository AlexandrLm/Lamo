import SwiftUI

struct WebSearchSettings: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "brave_search_api_key") ?? ""
    @State private var autoFetch: Bool = UserDefaults.standard.object(forKey: "web_auto_fetch") as? Bool ?? true
    @State private var showAPIKey = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Search Engine", systemImage: "magnifyingglass")
                    Spacer()
                    if !apiKey.isEmpty {
                        Text("Brave")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("DuckDuckGo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Brave Search provides better results with URL support. Free at brave.com/search/api.")
            }

            Section("Brave API Key (Optional)") {
                HStack {
                    if showAPIKey {
                        TextField("BRAVE_API_KEY", text: $apiKey)
                            .textContentType(.password)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        SecureField("BRAVE_API_KEY", text: $apiKey)
                    }

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    saveAPIKey()
                } label: {
                    Text("Save")
                }
                .disabled(apiKey.isEmpty)

                Button(role: .destructive) {
                    apiKey = ""
                    saveAPIKey()
                } label: {
                    Text("Clear Key")
                }
                .disabled(apiKey.isEmpty)
            }

            Section {
                Toggle(isOn: $autoFetch) {
                    Label("Auto-fetch top results", systemImage: "arrow.down.circle")
                }
                .onChange(of: autoFetch) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "web_auto_fetch")
                }
            } header: {
                Text("Options")
            } footer: {
                Text("When enabled, automatically loads full content from top 3 search results.")
            }

            Section("Test") {
                Button {
                    testSearch()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.circle")
                        }
                        Text("Test Search")
                    }
                }
                .disabled(isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("Error") ? .red : .green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAPIKey() {
        UserDefaults.standard.set(apiKey.isEmpty ? nil : apiKey, forKey: "brave_search_api_key")
    }

    private func testSearch() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let results = try await SearchProvider.shared.search(query: "Swift programming", maxResults: 3)
                if results.isEmpty {
                    testResult = "No results returned"
                } else {
                    testResult = "✅ Found \(results.count) results"
                    if let first = results.first, let title = first["title"] {
                        testResult = testResult! + "\nFirst: \(title)"
                    }
                }
            } catch {
                testResult = "❌ Error: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
