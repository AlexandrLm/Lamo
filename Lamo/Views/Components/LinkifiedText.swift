import SwiftUI
import SafariServices

/// Detects URLs in text and makes them tappable.
struct LinkifiedText: View {
    let text: String
    let baseURL: URL?

    @State private var showSafari = false
    @State private var selectedURL: URL?
    @State private var showWebView = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Render text with tappable links
            ForEach(Array(parseLinks().enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(content)
                case .link(let url, let display):
                    Button {
                        selectedURL = url
                        showWebView = true
                    } label: {
                        Text(display)
                            .foregroundStyle(.white)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showWebView) {
            if let url = selectedURL {
                SafariSheet(url: url)
            }
        }
    }

    private func parseLinks() -> [LinkSegment] {
        var segments: [LinkSegment] = []
        let pattern = #"https?://[^\s<>"\)]+"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.text(text)]
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        var lastEnd = text.startIndex

        for match in regex.matches(in: text, options: [], range: nsRange) {
            guard let range = Range(match.range, in: text) else { continue }

            // Add text before the link
            if lastEnd < range.lowerBound {
                segments.append(.text(String(text[lastEnd..<range.lowerBound])))
            }

            let urlString = String(text[range])
            if let url = URL(string: urlString) {
                segments.append(.link(url, urlString))
            } else {
                segments.append(.text(urlString))
            }

            lastEnd = range.upperBound
        }

        // Add remaining text
        if lastEnd < text.endIndex {
            segments.append(.text(String(text[lastEnd..<text.endIndex])))
        }

        return segments.isEmpty ? [.text(text)] : segments
    }
}

enum LinkSegment {
    case text(String)
    case link(URL, String)
}

/// Safari sheet for opening URLs
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - WebView Sheet (in-app browser)

/// Full in-app browser with navigation
struct InAppBrowserView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .navigationTitle(url.host ?? "Web")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                    }
                }
        }
    }
}

/// UIViewRepresentable wrapper for WKWebView
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
