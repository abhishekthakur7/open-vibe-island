import Foundation
import SwiftUI

/// A bounded, native renderer for agent-authored Markdown.
///
/// Foundation parses inline emphasis, links, and code. The small local parser
/// below owns the block grammar we display, so paragraph breaks, lists, code
/// fences, headings, and block quotes cannot collapse into one `Text` run.
/// Markdown images are reduced to their accessible alternative text before any
/// parsing; this renderer has no image provider and never loads a URL.
struct LocalMarkdownText: View {
    enum Style {
        case completionCard
        case flightDeckAssistant

        fileprivate var font: Font {
            switch self {
            case .completionCard:
                .system(size: 13.5, weight: .medium)
            case .flightDeckAssistant:
                .system(size: FlightDeckTypography.assistantSize, weight: .regular)
            }
        }

        fileprivate var codeFont: Font {
            switch self {
            case .completionCard:
                .system(size: 12.5, weight: .regular, design: .monospaced)
            case .flightDeckAssistant:
                .system(size: FlightDeckTypography.assistantSize - 1, weight: .regular, design: .monospaced)
            }
        }

        fileprivate var blockSpacing: CGFloat {
            switch self {
            case .completionCard: 7
            case .flightDeckAssistant: 6
            }
        }
    }

    struct OrderedListItem: Equatable {
        let ordinal: Int
        let text: String
    }

    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case unorderedList([String])
        case orderedList([OrderedListItem])
        case quote(String)
        case code(String)
    }

    let source: String
    let style: Style
    let colors: IslandColorTokens

    init(_ source: String, style: Style = .completionCard, colors: IslandColorTokens) {
        self.source = source
        self.style = style
        self.colors = colors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.blockSpacing) {
            ForEach(Array(Self.blocks(for: source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
        case .heading(let level, let text):
            inlineText(text, font: headingFont(for: level))
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(style.font)
                            .accessibilityHidden(true)
                        inlineText(item)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(item.ordinal).")
                            .font(style.font)
                            .frame(minWidth: 18, alignment: .trailing)
                            .accessibilityHidden(true)
                        inlineText(item.text)
                    }
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 9) {
                Rectangle()
                    .fill(colors.surfaceText.opacity(0.2))
                    .frame(width: 3)
                inlineText(text)
                    .foregroundStyle(colors.surfaceText.opacity(0.68))
            }
        case .code(let text):
            Text(text)
                .font(style.codeFont)
                .foregroundStyle(colors.surfaceText.opacity(0.88))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(colors.surfaceText.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func inlineText(_ source: String, font: Font? = nil) -> some View {
        Text(Self.attributedText(for: source))
            .font(font ?? style.font)
            .foregroundStyle(colors.surfaceText.opacity(style == .completionCard ? 0.88 : 0.9))
            .tint(style == .flightDeckAssistant ? colors.statusRunning : .blue)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .system(size: 16, weight: .bold)
        case 2: .system(size: 15, weight: .bold)
        default: .system(size: 14, weight: .semibold)
        }
    }

    /// Kept internal so block preservation and the no-image boundary have
    /// deterministic tests independent of SwiftUI rasterization.
    static func blocks(for source: String) -> [Block] {
        let lines = sanitizingImages(in: source).components(separatedBy: .newlines)
        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
            } else if trimmed.hasPrefix("```") {
                flushParagraph()
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(codeLines.joined(separator: "\n")))
            } else if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
            } else if let quote = quoteText(in: trimmed) {
                flushParagraph()
                var quoteLines = [quote]
                index += 1
                while index < lines.count, let nextQuote = quoteText(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    quoteLines.append(nextQuote)
                    index += 1
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
            } else if let item = unorderedItem(in: trimmed) {
                flushParagraph()
                var items = [item]
                index += 1
                while index < lines.count, let nextItem = unorderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextItem)
                    index += 1
                }
                blocks.append(.unorderedList(items))
            } else if let item = orderedItem(in: trimmed) {
                flushParagraph()
                var items = [item]
                index += 1
                while index < lines.count, let nextItem = orderedItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextItem)
                    index += 1
                }
                blocks.append(.orderedList(items))
            } else {
                paragraphLines.append(trimmed)
                index += 1
            }
        }

        flushParagraph()
        return blocks
    }

    static func attributedText(for source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: sanitizingImages(in: source), options: options)) ?? AttributedString(source)
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let markers = line.prefix { $0 == "#" }
        let level = markers.count
        guard (1...6).contains(level), line.dropFirst(level).first?.isWhitespace == true else { return nil }
        return (level, line.dropFirst(level).trimmingCharacters(in: .whitespaces))
    }

    private static func quoteText(in line: String) -> String? {
        guard line.first == ">" else { return nil }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private static func unorderedItem(in line: String) -> String? {
        guard line.count >= 2, ["-", "*", "+"].contains(line.first!), line.dropFirst().first?.isWhitespace == true else {
            return nil
        }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(in line: String) -> OrderedListItem? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty,
              let ordinal = Int(digits),
              let marker = line.dropFirst(digits.count).first,
              marker == "." || marker == ")"
        else {
            return nil
        }
        let remainder = line.dropFirst(digits.count + 1)
        guard remainder.first?.isWhitespace == true else { return nil }
        return OrderedListItem(ordinal: ordinal, text: remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func sanitizingImages(in source: String) -> String {
        let pattern = #"!\[([^\]]*)\]\([^\)]*\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return expression.stringByReplacingMatches(
            in: source,
            options: [],
            range: range,
            withTemplate: "$1"
        )
    }
}
