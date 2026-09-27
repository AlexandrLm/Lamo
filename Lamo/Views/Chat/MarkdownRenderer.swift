import SwiftUI
import Markdown

struct MarkdownRenderer: View {
    let text: String
    let textColor: Color
    let isStreaming: Bool
    private let doc: Markdown.Document

    init(text: String, textColor: Color, isStreaming: Bool = false) {
        self.text = text
        self.textColor = textColor
        self.isStreaming = isStreaming
        // Во время стриминга текст меняется на каждый токен — кэшировать
        // промежуточные документы бессмысленно, только засоряют кэш.
        self.doc = isStreaming ? Markdown.Document(parsing: text) : Self.cached(text)
    }

    var body: some View {
        if text.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<doc.childCount, id: \.self) { i in block(doc.child(at: i)!) }
                if isStreaming { StreamingCursor().padding(.top, 4) }
            }
        }
    }

    private static func cached(_ t: String) -> Markdown.Document {
        if let v = cache.object(forKey: t as NSString) { return v.doc }
        let d = Markdown.Document(parsing: t)
        cache.setObject(CacheVal(d), forKey: t as NSString, cost: t.utf8.count)
        return d
    }
    private static let cache: NSCache<NSString, CacheVal> = {
        let c = NSCache<NSString, CacheVal>()
        c.countLimit = 50; c.totalCostLimit = 2_097_152; return c
    }()
    private final class CacheVal { let doc: Markdown.Document; init(_ d: Markdown.Document) { doc = d } }

    /// Concrete-type firewall between the mutually recursive builders below
    /// (groupBlock ↔ listItem): keeps opaque-type inference decidable.
    private func block(_ m: Markup) -> AnyView {
        AnyView(groupBlock(m))
    }

    @ViewBuilder
    private func groupBlock(_ m: Markup) -> some View {
        if let h = m as? Heading {
            headingView(h)
        } else if let c = m as? Markdown.CodeBlock {
            CodeBlock(code: c.code, language: c.language ?? "").padding(.vertical, 8)
        } else if let html = m as? HTMLBlock {
            HTMLCard(html: html.rawHTML, title: nil).padding(.vertical, 8)
        } else if let p = m as? Paragraph {
            let t = p.format().trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { InlineMarkdown(text: t, textColor: textColor).padding(.bottom, 8) }
        } else if let bq = m as? BlockQuote {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(LamoTheme.Colors.accent.opacity(0.45)).frame(width: 2.5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<bq.childCount, id: \.self) { i in block(bq.child(at: i)!) }
                }
            }.padding(.leading, 4).padding(.vertical, 4)
        } else if m is ThematicBreak {
            ThinDivider().padding(.vertical, 12)
        } else if let ol = m as? OrderedList {
            let items = Array(ol.listItems)
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                listItem(item, indent: 0, idx: i + Int(ol.startIndex), ordered: true)
            }
        } else if let ul = m as? UnorderedList {
            let items = Array(ul.listItems)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                listItem(item, indent: 0, idx: 0, ordered: false)
            }
        } else if let t = m as? Markdown.Table {
            MarkdownTable(
                headers: Array(t.head.cells).map { $0.format() },
                rows: Array(t.body.rows).map { Array($0.cells).map { $0.format() } }
            ).padding(.vertical, 8)
        } else {
            let t = m.format().trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { InlineMarkdown(text: t, textColor: textColor).padding(.bottom, 8) }
        }
    }

    private func headingView(_ h: Heading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            InlineMarkdown(text: inlineStr(h), textColor: textColor, font: headerFont(h.level))
            if h.level <= 2 {
                ThinDivider()
            }
        }
        .padding(.top, h.level == 1 ? 16 : h.level == 2 ? 14 : 10)
        .padding(.bottom, h.level <= 2 ? 6 : 4)
    }

    @ViewBuilder
    private func listItem(_ item: ListItem, indent: Int, idx: Int, ordered: Bool) -> some View {
        let blks = Array(item.blockChildren)
        let inlines = blks.prefix(while: { $0 is Paragraph })
        let nested = blks.dropFirst(inlines.count)
        let txt = inlines.map { $0.format() }.joined(separator: "\n")
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    if let cb = item.checkbox {
                        Image(systemName: cb == .checked ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline)
                            .foregroundStyle(cb == .checked ? LamoTheme.Colors.textMedium : .secondary)
                            .frame(width: 18, alignment: .center)
                        InlineMarkdown(text: txt, textColor: textColor)
                            .foregroundStyle(cb == .checked ? .secondary : textColor)
                            .strikethrough(cb == .checked)
                    } else if ordered {
                        Text("\(idx).").font(.subheadline).foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        InlineMarkdown(text: txt, textColor: textColor)
                    } else {
                        Text(bullet(indent)).font(.system(size: 10))
                            .foregroundStyle(indent == 0 ? LamoTheme.Colors.textMedium : LamoTheme.Colors.textFaint)
                            .frame(width: 18, alignment: .center).padding(.top, 4)
                        InlineMarkdown(text: txt, textColor: textColor)
                    }
                }
                .padding(.leading, CGFloat(indent) * 18).padding(.vertical, 2)
                ForEach(Array(nested.enumerated()), id: \.offset) { _, child in
                    if let ol = child as? OrderedList {
                        let si = Array(ol.listItems)
                        ForEach(Array(si.enumerated()), id: \.offset) { j, sub in
                            listItem(sub, indent: indent + 1, idx: j + Int(ol.startIndex), ordered: true)
                        }
                    } else if let ul = child as? UnorderedList {
                        let si = Array(ul.listItems)
                        ForEach(Array(si.enumerated()), id: \.offset) { _, sub in
                            listItem(sub, indent: indent + 1, idx: 0, ordered: false)
                        }
                    } else { block(child) }
                }
            }
        )
    }

    private func inlineStr(_ m: Markup) -> String {
        let s = m.format()
        if let h = m as? Heading { return String(s.dropFirst(h.level + 1)) }
        return s
    }

    private func headerFont(_ lv: Int) -> Font {
        let fonts: [Font] = [.title3, .headline, .subheadline, .footnote, .caption, .caption2]
        return fonts[max(0, min(lv - 1, 5))].bold()
    }

    private func bullet(_ indent: Int) -> String {
        indent == 0 ? "\u{2022}" : indent == 1 ? "\u{25E6}" : "\u{25AA}"
    }
}

private struct InlineMarkdown: View {
    let text: String
    let textColor: Color
    var font: Font = .subheadline

    /// Кэш разобранных AttributedString: парсинг markdown на каждый токен
    /// стриминга — самая дорогая операция рендера длинных ответов.
    /// Стили не зависят от textColor/font (ссылки красятся через .tint),
    /// поэтому ключ — только текст.
    private static let styledCache: NSCache<NSString, StyledVal> = {
        let c = NSCache<NSString, StyledVal>()
        c.countLimit = 200; c.totalCostLimit = 1_048_576; return c
    }()
    private final class StyledVal { let s: AttributedString; init(_ s: AttributedString) { self.s = s } }

    private static func styled(_ text: String) -> AttributedString {
        if let v = styledCache.object(forKey: text as NSString) { return v.s }
        var s = (try? AttributedString(markdown: text)) ?? AttributedString(text)
        for run in s.runs {
            if let i = run.inlinePresentationIntent, i.contains(.code) {
                s[run.range].backgroundColor = LamoTheme.Colors.fillMedium
                s[run.range].font = .system(.footnote, design: .monospaced)
                s[run.range].foregroundColor = LamoTheme.Colors.textMedium
            }
            if run.link != nil {
                s[run.range].underlineStyle = .single
            }
        }
        styledCache.setObject(StyledVal(s), forKey: text as NSString, cost: text.utf8.count)
        return s
    }

    var body: some View {
        Text(Self.styled(text))
            .font(font)
            .foregroundStyle(textColor)
            .tint(LamoTheme.Colors.accent)
            .lineSpacing(5)
            .textSelection(.enabled)
    }
}

struct StreamingCursor: View {
    @State private var visible = true
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(LamoTheme.Colors.textMedium).frame(width: 2, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    visible.toggle()
                }
            }
    }
}

struct CodeBlock: View {
    let code: String
    let language: String
    @State private var copied = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .foregroundStyle(LamoTheme.Colors.textLow)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    task?.cancel()
                    withAnimation { copied = true }
                    task = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption2)
                        Text(copied ? "Copied" : "Copy").font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(copied ? LamoTheme.Colors.textMedium : LamoTheme.Colors.textFaint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(LamoTheme.Colors.textMedium)
                    .textSelection(.enabled).padding(12)
            }
        }
        .glassEffect(.regular.tint(LamoTheme.Colors.fillSubtle),
                     in: .rect(cornerRadius: 10))
    }
}

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]
    private var ncol: Int { max(headers.count, rows.map(\.count).max() ?? 0) }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<ncol, id: \.self) { c in
                        MarkdownTableCell(text: c < headers.count ? headers[c] : "", isHeader: true)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                }
                Rectangle().fill(LamoTheme.Colors.separator.opacity(0.5)).frame(height: 0.5)
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    GridRow {
                        ForEach(0..<ncol, id: \.self) { c in
                            MarkdownTableCell(text: c < row.count ? row[c] : "", isHeader: false)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                        }
                    }
                    .background(i % 2 == 0 ? Color.clear : LamoTheme.Colors.fillSubtle)
                    if i < rows.count - 1 {
                        Rectangle().fill(LamoTheme.Colors.separator.opacity(0.35))
                            .frame(height: 0.5).padding(.horizontal, 10)
                    }
                }
            }.frame(minWidth: 280)
        }
        .glassEffect(.regular.tint(LamoTheme.Colors.fillSubtle),
                     in: .rect(cornerRadius: 10, style: .continuous))
    }
}

private struct MarkdownTableCell: View {
    let text: String
    let isHeader: Bool
    var body: some View {
        Group {
            if let a = try? AttributedString(markdown: text) { SwiftUI.Text(a) } else { SwiftUI.Text(text) }
        }
        .font(isHeader ? .footnote.weight(.semibold) : .footnote)
        .foregroundStyle(isHeader ? LamoTheme.Colors.textMedium
                         : LamoTheme.Colors.textPrimary.opacity(0.85))
        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 44, alignment: .leading).textSelection(.enabled)
    }
}
