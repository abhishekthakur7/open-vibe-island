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
        /// Halo `.assistant` (G-69): 12.5 / line-height 1.55 at `--t2`, with inline
        /// `code` runs on their own `white@.07` chip in `#c8d2e6` ink at 11pt.
        case haloAssistant
        /// Poured §D `.assistant` (Slice 5 · D1, `01-poured-island.html:433-439`):
        /// `font-size:12.5px; line-height:1.55; color:rgba(242,245,251,.66)` with
        /// `strong{color:rgba(242,245,251,.96); font-weight:640}` and
        /// `code{font-size:11px; background:rgba(255,255,255,.06); border-radius:4px;
        /// color:#c9d3e6}`. Mirrors `.haloAssistant`'s shape at Poured's own values —
        /// the §D detail used to borrow `.completionCard` (13.5/medium, 12.5 mono,
        /// no chip), which rendered the board's quiet prose as a loud card body.
        case pouredAssistant

        fileprivate var font: Font {
            switch self {
            case .completionCard:
                .system(size: 13.5, weight: .medium)
            case .flightDeckAssistant:
                .system(size: FlightDeckTypography.assistantSize, weight: .regular)
            case .haloAssistant:
                .system(size: HaloTypography.assistantSize, weight: .regular)
            case .pouredAssistant:
                PouredType.Role.assistantBody.font
            }
        }

        fileprivate var codeFont: Font {
            switch self {
            case .completionCard:
                .system(size: 12.5, weight: .regular, design: .monospaced)
            case .flightDeckAssistant:
                .system(size: FlightDeckTypography.assistantSize - 1, weight: .regular, design: .monospaced)
            case .haloAssistant:
                .system(size: HaloTypography.assistantInlineCodeSize, weight: .regular, design: .monospaced)
            case .pouredAssistant:
                PouredType.Role.assistantInlineCode.font
            }
        }

        fileprivate var blockSpacing: CGFloat {
            switch self {
            case .completionCard: 7
            case .flightDeckAssistant: 6
            case .haloAssistant: 6
            // `.assistant ul{margin:6px 0 2px}` — the board's own block gap.
            case .pouredAssistant: 6
            }
        }

        /// Body ink opacity — Halo's assistant block is a **quote**, so it sits at
        /// `--t2` (0.63) rather than near-`--t1` like the other two surfaces.
        fileprivate var bodyOpacity: Double {
            switch self {
            case .completionCard: 0.88
            case .flightDeckAssistant: 0.9
            case .haloAssistant: 0.63
            // `.assistant{color:rgba(242,245,251,.66)}` (`:433`).
            case .pouredAssistant: 0.66
            }
        }

        fileprivate var lineSpacing: CGFloat {
            switch self {
            // 12.5 × 1.55 ≈ 19.4pt line box → ≈ 4pt of added leading.
            case .haloAssistant, .pouredAssistant: 4
            default: 0
            }
        }

        /// Whether inline `code` runs get the mockup's chip.
        fileprivate var chipsInlineCode: Bool {
            self == .haloAssistant || self == .pouredAssistant
        }

        /// The inline-code chip's ink. Halo `#c8d2e6`; Poured `#c9d3e6` (`:439`).
        fileprivate var inlineCodeInk: Color {
            switch self {
            case .pouredAssistant:
                Color(red: 0xC9 / 255.0, green: 0xD3 / 255.0, blue: 0xE6 / 255.0)
            default:
                Color(red: 0xC8 / 255.0, green: 0xD2 / 255.0, blue: 0xE6 / 255.0)
            }
        }

        /// The inline-code chip's fill. Halo `white@.07`; Poured `white@.06` (`:438`).
        fileprivate var inlineCodeFill: Double {
            switch self {
            case .pouredAssistant: 0.06
            default: 0.07
            }
        }

        /// `.assistant strong{color:rgba(242,245,251,.96); font-weight:640}` (`:437`) —
        /// the board lifts emphasis out of the body's 0.66 ink onto near-`--t1` and a
        /// heavier face. Only Poured states it; every other style leaves Foundation's
        /// parsed `**strong**` alone.
        fileprivate var strongOpacity: Double? {
            self == .pouredAssistant ? 0.96 : nil
        }

        fileprivate var strongFont: Font? {
            guard self == .pouredAssistant else { return nil }
            // Spec weight 640 → the nearest SF Pro face is `.semibold`, the same
            // rounding `PouredType.Spec.fontWeight` applies to every 600–650 role.
            return .system(size: PouredType.Role.assistantBody.spec.size, weight: .semibold)
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
        Text(styledInline(source))
            .font(font ?? style.font)
            .lineSpacing(style.lineSpacing)
            .foregroundStyle(colors.surfaceText.opacity(style.bodyOpacity))
            .tint(style == .flightDeckAssistant ? colors.statusRunning : .blue)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Gives inline `code` runs the mockup's chip (G-69) where the style asks for
    /// it — `white@.07` background, `#c8d2e6` ink, 11pt mono. Every other style
    /// gets the parsed markdown untouched.
    private func styledInline(_ source: String) -> AttributedString {
        var attributed = Self.attributedText(for: source)

        // `.assistant strong` — Poured only; applied before the code pass so an
        // inline `code` run nested inside emphasis still ends up on its chip.
        if let strongFont = style.strongFont, let strongOpacity = style.strongOpacity {
            for run in attributed.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                attributed[run.range].font = strongFont
                attributed[run.range].foregroundColor = colors.surfaceText.opacity(strongOpacity)
            }
        }

        guard style.chipsInlineCode else { return attributed }
        let ink = style.inlineCodeInk
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].font = style.codeFont
            attributed[run.range].foregroundColor = ink
            attributed[run.range].backgroundColor = Color.white.opacity(style.inlineCodeFill)
        }
        return attributed
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
