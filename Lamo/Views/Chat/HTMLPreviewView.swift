import SwiftUI
import WebKit
#if os(iOS)
import UIKit
#endif

// MARK: - HTML Card (main entry point)

/// Polished HTML preview card with toolbar, source toggle, expand, and copy.
struct HTMLCard: View {
    let html: String
    var title: String? = nil
    var maxHeight: CGFloat = 420

    @State private var showSource = false
#if os(iOS)
    @State private var isFullScreen = false
#endif

    private let accent = Color(red: 0.25, green: 0.60, blue: 0.95)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if showSource {
                sourceView
            } else {
                HTMLPreviewView(html: html, maxHeight: maxHeight)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(
                LinearGradient(
                    colors: [accent.opacity(0.3), accent.opacity(0.05), Color.white.opacity(0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
#if os(iOS)
        .fullScreenCover(isPresented: $isFullScreen) { fullScreenView }
#endif
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title ?? "HTML Preview")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(html.count) chars")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            Spacer()

            // Source / Rendered segmented toggle
            HStack(spacing: 0) {
                tbBtn("doc.text", active: showSource) { showSource = true }
                tbBtn("eye", active: !showSource) { showSource = false }
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.06), lineWidth: 0.5))

#if os(iOS)
            tbBtn("arrow.up.left.and.arrow.down.right") { isFullScreen = true }.padding(.leading, 4)
#endif

            tbBtn("doc.on.doc", action: {
#if os(iOS)
                UIPasteboard.general.string = html
#endif
            }).padding(.leading, 2)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func tbBtn(_ icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? .white : .secondary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? accent.opacity(0.3) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source View

    private var sourceView: some View {
        ScrollView(.vertical) {
            Text(html)
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .frame(maxHeight: maxHeight).background(Color.black.opacity(0.3))
    }

    // MARK: - Full Screen (iOS only)

#if os(iOS)
    private var fullScreenView: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            HTMLPreviewView(html: html, maxHeight: 2000, cornerRadius: 0).ignoresSafeArea(edges: .bottom)
            Button {
                isFullScreen = false
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40).background(Circle().fill(.ultraThinMaterial)).shadow(radius: 8)
            }
            .padding(.top, 16).padding(.trailing, 16)
        }
    }
#endif
}


// MARK: - HTML Preview View (WKWebView)

struct HTMLPreviewView: View {
    let html: String
    var maxHeight: CGFloat = 320
    var cornerRadius: CGFloat = 12

    @State private var contentHeight: CGFloat = 160

    var body: some View {
        HTMLWebView(html: wrapHTML(html), contentHeight: $contentHeight)
            .frame(height: min(contentHeight, maxHeight))
            .animation(.easeInOut(duration: 0.3), value: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func wrapHTML(_ raw: String) -> String {
        if raw.lowercased().contains("<html") || raw.lowercased().contains("<!doctype") {
            return injectDarkStyles(raw)
        }
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root{color-scheme:dark}*{box-sizing:border-box;margin:0;padding:0}
        html{font-size:14px;-webkit-text-size-adjust:100%}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#141414;color:#e5e5e7;padding:14px 16px;line-height:1.6}
        a{color:#64d2ff;text-decoration:none}
        img,video,svg{max-width:100%;height:auto;border-radius:8px;margin:8px 0}
        table{width:100%;border-collapse:collapse;margin:10px 0;font-size:.88em}
        th,td{border:1px solid #3a3a3c;padding:8px 12px;text-align:left}
        th{background:#2c2c2e;font-weight:600;color:#fff}
        tr:nth-child(even) td{background:#222224}
        code,pre{font-family:'SF Mono',Menlo,Monaco,monospace}
        code{background:#2c2c2e;padding:2px 6px;border-radius:4px;font-size:.9em;color:#f5a97f}
        pre{background:#000;border:1px solid #333;border-radius:10px;padding:12px;overflow-x:auto;white-space:pre-wrap;font-size:.85em;line-height:1.5}
        pre code{background:none;padding:0;color:#e5e5e7}
        h1,h2,h3{margin:14px 0 6px;font-weight:600;line-height:1.3}
        h1{font-size:1.5em;color:#fff}h2{font-size:1.25em}h3{font-size:1.1em}
        p{margin:6px 0}ul,ol{padding-left:22px;margin:6px 0}li{margin:4px 0}
        blockquote{border-left:3px solid #0ea37f;padding:6px 14px;margin:10px 0;color:#acacb0;background:rgba(14,163,127,0.05);border-radius:0 6px 6px 0}
        hr{border:none;border-top:1px solid #3a3a3c;margin:14px 0}
        </style></head><body>\(raw)</body></html>
        """
    }

    private func injectDarkStyles(_ raw: String) -> String {
        let style = "<style>:root{color-scheme:dark}body{font-family:-apple-system,sans-serif;background:#141414!important;color:#e5e5e7!important;padding:14px 16px;line-height:1.6}a{color:#64d2ff!important}img,video,svg{max-width:100%;height:auto}table{width:100%;border-collapse:collapse}th,td{border:1px solid #3a3a3c;padding:8px 12px}th{background:#2c2c2e}code,pre{font-family:'SF Mono',Menlo,monospace}pre{background:#000;border:1px solid #333;border-radius:10px;padding:12px;overflow-x:auto}</style>"
        if let headEnd = raw.range(of: "</head>") {
            var result = raw
            result.replaceSubrange(headEnd, with: "\(style)\n</head>")
            return result
        }
        return raw.replacingOccurrences(of: "<head>", with: "<head>\(style)")
    }
}

// MARK: - WKWebView Representable

#if os(iOS)
private struct HTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: "height")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.isOpaque = false
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        view.scrollView.backgroundColor = .clear
        view.allowsLinkPreview = false
        view.allowsBackForwardNavigationGestures = false
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_: WKWebView, context _: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: HTMLWebView
        init(parent: HTMLWebView) { self.parent = parent }


        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Use MutationObserver for dynamic content, with fallback
            let js = """
            (function(){
                var report = function(){ return document.body.scrollHeight; };
                var h = report();
                if (h > 0) { window.webkit.messageHandlers.height.postMessage({height:h}); }
                var ro = new ResizeObserver(function(entries){
                    for (var e of entries) {
                        var h2 = e.target.scrollHeight;
                        if (h2 > 0) { window.webkit.messageHandlers.height.postMessage({height:h2}); }
                    }
                });
                ro.observe(document.body);
                // Also observe after images/iframes load
                document.querySelectorAll('img,iframe,video').forEach(function(el){
                    el.addEventListener('load', function(){
                        window.webkit.messageHandlers.height.postMessage({height:document.body.scrollHeight});
                    });
                    el.addEventListener('error', function(){
                        window.webkit.messageHandlers.height.postMessage({height:document.body.scrollHeight});
                    });
                });
                return h;
            })();
            """
            webView.evaluateJavaScript(js) { result, _ in
                if let h = result as? CGFloat, h > 0 {
                    DispatchQueue.main.async { self.parent.contentHeight = h + 8 }
                }
            }
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "height", let body = message.body as? [String: Any],
               let h = body["height"] as? CGFloat, h > 0 {
                DispatchQueue.main.async { self.parent.contentHeight = h + 8 }
            }
        }

        func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}
#else
private struct HTMLWebView: View {
    let html: String
    @Binding var contentHeight: CGFloat
    var body: some View {
        Text("HTML preview not available on macOS").font(.caption).foregroundStyle(.tertiary)
            .onAppear { contentHeight = 40 }
    }
}
#endif

// MARK: - HTML Detection

enum HTMLDetector {
    /// Returns true only if the text is predominantly HTML — starts with a tag or doctype,
    /// and at least 60% of the content is inside HTML tags.
    static func isHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else { return false }
        // Must start with < (tag or doctype)
        guard trimmed.hasPrefix("<") || trimmed.hasPrefix("<!") else { return false }
        let tagPattern = #"</?[a-zA-Z][a-zA-Z0-9]*(?:\s[^>]*)?>"#
        guard let regex = try? NSRegularExpression(pattern: tagPattern) else { return false }
        let fullRange = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, range: fullRange)
        guard matches.count >= 2 else { return false }
        // Calculate how much of the text is covered by HTML tags + their content
        // Simple heuristic: first tag near position 0, last closing tag near the end
        // DOCTYPE docs have the first real tag further in
        let firstTagMax = trimmed.hasPrefix("<!") ? 20 : 5
        if let first = matches.first?.range, first.location <= firstTagMax,
           let last = matches.last?.range {
            let lastEnd = last.location + last.length
            // Last tag should be near the end of the text
            return lastEnd >= trimmed.count - 10
        }
        return false
    }

    static func extractFromCodeBlock(_ text: String) -> String? {
        let pattern = #"```html?\s*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
