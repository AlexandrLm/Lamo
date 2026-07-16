import SwiftUI

struct WebSearchSettings: View {
    @State private var apiKey: String = KeychainHelper.load(key: "brave_search_api_key") ?? ""
    @State private var autoFetch: Bool = UserDefaults.standard.object(forKey: "web_auto_fetch") as? Bool ?? true
    @State private var showAPIKey = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.lg) {
                // ── Engine Status ──
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                    sectionHeader("SEARCH ENGINE")

                    HStack {
                        Text("Active")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        if !apiKey.isEmpty {
                            Text("SearXNG + Brave")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            Text("SearXNG")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                // ── Brave API Key ──
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                    sectionHeader("BRAVE API KEY (OPTIONAL)")

                    HStack {
                        if showAPIKey {
                            TextField("BRAVE_API_KEY", text: $apiKey)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            SecureField("BRAVE_API_KEY", text: $apiKey)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white)
                        }

                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    HStack(spacing: LamoTheme.Spacing.md) {
                        Button {
                            saveAPIKey()
                        } label: {
                            Text("Save")
                                .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(apiKey.isEmpty)

                        Button {
                            apiKey = ""
                            saveAPIKey()
                        } label: {
                            Text("Clear")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
                        }
                        .disabled(apiKey.isEmpty)
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                // ── Options ──
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                    sectionHeader("OPTIONS")

                    Toggle(isOn: $autoFetch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-fetch top results")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("Loads full content from top 3 results")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .tint(.white.opacity(0.7))
                    .onChange(of: autoFetch) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "web_auto_fetch")
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))

                // ── Test ──
                VStack(alignment: .leading, spacing: LamoTheme.Spacing.md) {
                    sectionHeader("TEST")

                    Button {
                        testSearch()
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white.opacity(0.5))
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                            }
                            Text(isTesting ? "Testing…" : "Run Test Search")
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: LamoTheme.CornerRadius.md))
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .textSelection(.enabled)
                    }
                }
                .padding(LamoTheme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.bottom, LamoTheme.Spacing.xxxl)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
            .textCase(.uppercase)
    }

    private func saveAPIKey() {
        if apiKey.isEmpty {
            KeychainHelper.delete(key: "brave_search_api_key")
        } else {
            KeychainHelper.save(key: "brave_search_api_key", value: apiKey)
        }
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
                    var text = "Found \(results.count) results"
                    if let first = results.first, let title = first["title"] {
                        text += "\nFirst: \(title)"
                    }
                    testResult = text
                }
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
