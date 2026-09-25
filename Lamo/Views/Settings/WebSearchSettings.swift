import SwiftUI

struct WebSearchSettings: View {
    @State private var apiKey: String = KeychainHelper.load(key: "brave_search_api_key") ?? ""
    @State private var autoFetch: Bool = AppDefaults.webAutoFetch.wrappedValue
    @State private var showAPIKey = false
    @State private var testQuery = "Swift programming"
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        ScrollView {
            VStack(spacing: LamoTheme.Spacing.md) {
                statusCard
                keyCard
                optionsTestCard
            }
            .padding(.horizontal, LamoTheme.Spacing.lg)
            .padding(.vertical, LamoTheme.Spacing.md)
        }
        .background(LamoTheme.Colors.background)
        .navigationTitle("Web Search")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Status (одна строка вместо целой карточки)

    private var statusCard: some View {
        HStack(spacing: LamoTheme.Spacing.sm) {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(LamoTheme.Colors.textMedium)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("Search engine")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LamoTheme.Colors.textHigh)
                Text(apiKey.isEmpty ? "Built-in SearXNG · Free" : "SearXNG + Brave · Faster")
                    .font(.caption)
                    .foregroundStyle(LamoTheme.Colors.textLow)
            }
            Spacer()
            Text(apiKey.isEmpty ? "FREE" : "PRO")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(LamoTheme.Colors.textMedium)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(LamoTheme.Colors.fillSubtle, in: Capsule())
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Key (автосейв вместо Save/Clear с багом disabled)

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: String(localized: "Brave key · optional"), icon: "key.fill")
                .padding(.bottom, LamoTheme.Spacing.sm)

            HStack {
                if showAPIKey {
                    TextField("Brave API key", text: $apiKey)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                } else {
                    SecureField("Brave API key", text: $apiKey)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                }

                Button { showAPIKey.toggle() } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .font(.subheadline)
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
                .buttonStyle(.plain)

                if !apiKey.isEmpty {
                    Button {
                        apiKey = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(LamoTheme.Colors.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onChange(of: apiKey) { _, newValue in
                // Сохраняем сразу: убраны кнопки Save/Clear, которые блокировали
                // очистку (Save был disabled при пустом поле).
                saveAPIKey(newValue)
            }

            Link(destination: URL(string: "https://brave.com/search/api/")!) {
                HStack(spacing: 4) {
                    Text("Get a free key at brave.com")
                        .font(.caption)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(LamoTheme.Colors.textLow)
            }
            .padding(.top, 8)
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Options + Test (одна карточка с разделителем)

    private var optionsTestCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $autoFetch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-fetch top results")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textHigh)
                    Text("Loads short excerpts from top 2 results")
                        .font(.caption)
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
            }
            .tint(LamoTheme.Colors.accent)
            .onChange(of: autoFetch) { _, newValue in
                AppDefaults.webAutoFetch.wrappedValue = newValue
            }
            .padding(.vertical, 4)

            ThinDivider()
                .padding(.vertical, LamoTheme.Spacing.sm)

            Text("Test query")
                .font(.caption.weight(.medium))
                .foregroundStyle(LamoTheme.Colors.textLow)
            TextField("Try a search…", text: $testQuery)
                .font(.subheadline)
                .foregroundStyle(LamoTheme.Colors.textHigh)
                .padding(10)
                .background(LamoTheme.Colors.fillSubtle, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 6)

            Button {
                testSearch()
            } label: {
                HStack(spacing: 8) {
                    if isTesting {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(LamoTheme.Colors.textMedium)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.caption)
                    }
                    Text(isTesting ? "Testing…" : "Run test")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(LamoTheme.Colors.textHigh)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(LamoTheme.Colors.fillSubtle, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isTesting || testQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 8)

            if let result = testResult {
                Text(result)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                    .textSelection(.enabled)
                    .padding(.top, 8)
            }
        }
        .padding(LamoTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: LamoTheme.CornerRadius.lg))
    }

    // MARK: - Helpers

    private func saveAPIKey(_ value: String = "") {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.delete(key: "brave_search_api_key")
        } else {
            KeychainHelper.save(key: "brave_search_api_key", value: trimmed)
        }
    }

    private func testSearch() {
        let query = testQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isTesting = true
        testResult = nil

        Task {
            do {
                let results = try await SearchProvider.shared.search(query: query, maxResults: 3)
                if results.isEmpty {
                    testResult = String(localized: "No results returned")
                } else {
                    var text = String(localized: "Found \(results.count) results")
                    if let first = results.first, let title = first["title"] {
                        text += String(localized: "\nFirst: \(title)")
                    }
                    testResult = text
                }
            } catch {
                testResult = String(localized: "Error: \(error.localizedDescription)")
            }
            isTesting = false
        }
    }
}
