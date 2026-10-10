import SwiftUI

/// 轻量 Markdown 渲染：标题、列表、任务列表、引用、代码块、分隔线，以及行内的粗体 / 斜体 / 代码 / 链接
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            inline(content)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .paragraph(let content):
            inline(content)
        case .bullet(let indent, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(indent == 0 ? "•" : "◦").foregroundStyle(.secondary)
                inline(content)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .numbered(let indent, let number, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                inline(content)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .task(let indent, let done, let content):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(done ? Color.green : .secondary)
                inline(content)
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let content):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                inline(content).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let content):
            Text(content)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
        case .rule:
            Divider().padding(.vertical, 2)
        case .spacer:
            Color.clear.frame(height: 2)
        }
    }

    private func inline(_ source: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: source, options: options) {
            return Text(attributed)
        }
        return Text(source)
    }
}

enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(indent: Int, String)
    case numbered(indent: Int, number: Int, String)
    case task(indent: Int, done: Bool, String)
    case quote(String)
    case code(String)
    case rule
    case spacer

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]? = nil

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flushParagraph()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(rawLine)
                continue
            }

            let leading = rawLine.prefix(while: { $0 == " " || $0 == "\t" })
            let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2

            if trimmed.isEmpty {
                flushParagraph()
                if blocks.last != .spacer && !blocks.isEmpty { blocks.append(.spacer) }
            } else if let heading = Self.heading(trimmed) {
                flushParagraph()
                blocks.append(heading)
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
            } else if let task = Self.task(trimmed, indent: indent) {
                flushParagraph()
                blocks.append(task)
            } else if let marker = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
                flushParagraph()
                blocks.append(.bullet(indent: indent, String(trimmed.dropFirst(marker.count))))
            } else if let numbered = Self.numbered(trimmed, indent: indent) {
                flushParagraph()
                blocks.append(numbered)
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flushParagraph()
        while blocks.last == .spacer { blocks.removeLast() }
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func task(_ line: String, indent: Int) -> MarkdownBlock? {
        for prefix in ["- [ ] ", "* [ ] ", "- [x] ", "* [x] ", "- [X] ", "* [X] "] where line.hasPrefix(prefix) {
            return .task(indent: indent, done: !prefix.contains("[ ]"), String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private static func numbered(_ line: String, indent: Int) -> MarkdownBlock? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return .numbered(indent: indent, number: number, String(rest.dropFirst(2)))
    }
}
