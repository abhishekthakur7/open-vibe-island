import SwiftUI
import OpenIslandCore

/// A themed, structurally consistent inline renderer for `PermissionDiffResult`.
///
/// The renderer deliberately owns both the line-number gutter and the marker
/// column.  A theme may tune their width and colours through `IslandDiffStyle`,
/// but cannot omit either column or fold the marker into the source text.
struct IslandDiffRenderer: View {
    let result: PermissionDiffResult
    let lang: LanguageManager
    let style: IslandDiffStyle

    /// Prevent a generated file from constructing an unbounded SwiftUI stack.
    static let maxRenderedLines = 500
    /// A long diff scrolls in place rather than stretching its permission card.
    static let maxHeight: CGFloat = 180

    /// A presentation-independent row contract that keeps the structural
    /// requirements testable without snapshotting a SwiftUI tree.
    struct RowModel: Identifiable {
        let id: Int
        let line: PermissionDiffLine
        let gutter: Int
        let marker: String
    }

    static func marker(for kind: PermissionDiffLine.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "\u{2212}"
        case .unchanged: ""
        }
    }

    /// Numbers removed lines on the old side and added/unchanged lines on the
    /// new side, matching a familiar unified-diff gutter.  The `gutter` field
    /// is non-optional so every rendered row necessarily owns a gutter cell.
    static func rows(for result: PermissionDiffResult) -> [RowModel] {
        var rows: [RowModel] = []
        var oldLineNumber = 1
        var newLineNumber = 1

        for (index, line) in result.lines.prefix(maxRenderedLines).enumerated() {
            let gutter: Int
            switch line.kind {
            case .removed:
                gutter = oldLineNumber
                oldLineNumber += 1
            case .added:
                gutter = newLineNumber
                newLineNumber += 1
            case .unchanged:
                gutter = newLineNumber
                oldLineNumber += 1
                newLineNumber += 1
            }
            rows.append(RowModel(id: index, line: line, gutter: gutter, marker: marker(for: line.kind)))
        }
        return rows
    }

    private var rows: [RowModel] { Self.rows(for: result) }
    /// Rows the renderer itself dropped, plus any a caller clamped away before
    /// handing the result in (`style.additionalHiddenLines`) — the Poured hero
    /// pre-clamps to whole `.dl` rows, and states the remainder here, inside the
    /// well, rather than as a floating line below it.
    private var hiddenLineCount: Int { result.lines.count - rows.count + style.additionalHiddenLines }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            AutoHeightScrollView(maxHeight: Self.maxHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        IslandDiffLineRow(row: row, style: style)
                    }
                    if hiddenLineCount > 0 {
                        Text(lang.t("approval.diffMoreLines", hiddenLineCount))
                            .font(style.font)
                            .foregroundStyle(style.context.content.opacity(0.6))
                            .padding(.horizontal, style.horizontalPadding)
                            .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, style.scrollVerticalPadding ?? 3)
            }
        }
        .background(style.containerShape.fill(style.containerBackground))
        .overlay {
            if let border = style.containerBorder {
                style.containerShape.strokeBorder(border.color, lineWidth: border.width)
            }
        }
        .clipShape(style.containerShape)
    }

    private var header: some View {
        let header = style.header
        return HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(header?.iconFont ?? style.font)
                .opacity(header?.iconOpacity ?? 1)
                .accessibilityHidden(true)
            switch Self.resolvedHeader(style: style, result: result, lang: lang) {
            case let .fileName(title):
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case let .updatedCounts(title, added, removed):
                Text(title)
                Text("+\(added)")
                    .foregroundStyle(style.added.content)
                Text("\u{2212}\(removed)")
                    .foregroundStyle(style.removed.content)
            }
        }
        .font(header?.font ?? style.font)
        .foregroundStyle(header?.color ?? style.headerColor)
        .padding(.horizontal, header?.horizontalPadding ?? style.horizontalPadding)
        .padding(.vertical, header?.verticalPadding ?? 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(header?.background ?? style.headerBackground)
        .overlay(alignment: .bottom) {
            if let border = header?.bottomBorder {
                Rectangle().fill(border.color).frame(height: border.width)
            }
        }
    }

    /// The header's resolved shape, split from SwiftUI so a theme's copy is
    /// pinnable without snapshotting a view: `.fileName` is a single truncating
    /// title line; `.updatedCounts` is the `Updated` word followed by the two
    /// `+N` / `−N` count chips.
    enum ResolvedHeader: Equatable {
        case fileName(String)
        case updatedCounts(title: String, added: Int, removed: Int)
    }

    static func resolvedHeader(
        style: IslandDiffStyle,
        result: PermissionDiffResult,
        lang: LanguageManager
    ) -> ResolvedHeader {
        func updated(_ title: String) -> ResolvedHeader {
            .updatedCounts(title: title, added: result.addedCount, removed: result.removedCount)
        }
        guard let header = style.header else {
            return updated(lang.t("approval.diffUpdated"))
        }
        switch header.title {
        case .updatedCounts:
            return updated(lang.t("approval.diffUpdated"))
        case let .haloFile(affectedPath):
            guard let path = affectedPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
                return .fileName(lang.t("island.halo.approval.diffFileFallback"))
            }
            let fileName = (path as NSString).lastPathComponent
            return .fileName(lang.t("island.halo.approval.diffFile", fileName, result.addedCount + result.removedCount))
        case let .pouredFile(fileName, hunk):
            return .fileName(pouredDiffHeaderTitle(fileName: fileName, hunk: hunk, lang: lang))
        }
    }

    /// The Poured `.fname` copy — `<file leaf> · <hunk>` when both are present,
    /// gracefully shedding either half rather than emitting a dangling `·`.
    /// The factory only selects this title when a hunk exists, so the no-hunk
    /// path resolves through the header-less `Updated` counts branch above.
    static func pouredDiffHeaderTitle(fileName: String?, hunk: String?, lang: LanguageManager) -> String {
        let path = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let leaf = path.isEmpty ? nil : (path as NSString).lastPathComponent
        let hunk = hunk?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (leaf, hunk.flatMap { $0.isEmpty ? nil : $0 }) {
        case let (leaf?, hunk?):
            return lang.t("island.poured.approval.diffFile", leaf, hunk)
        case let (leaf?, nil):
            return leaf
        case let (nil, hunk?):
            return hunk
        case (nil, nil):
            return lang.t("approval.diffUpdated")
        }
    }
}

/// The three structural cells of an inline diff row.  Keeping the marker in its
/// own view makes it impossible for source content beginning with `+` or `-` to
/// masquerade as a diff marker.
private struct IslandDiffLineRow: View {
    let row: IslandDiffRenderer.RowModel
    let style: IslandDiffStyle

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            IslandDiffGutter(number: row.gutter, colors: style.colors(for: row.line.kind), width: style.gutterWidth)
            IslandDiffMarker(kind: row.line.kind, colors: style.colors(for: row.line.kind), width: style.markerWidth)
            Text(row.line.text.isEmpty ? " " : row.line.text)
                .foregroundStyle(style.colors(for: row.line.kind).content)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(style.font)
        .padding(.leading, style.horizontalPadding)
        .padding(.trailing, style.rowTrailingPadding ?? style.horizontalPadding)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.colors(for: row.line.kind).background)
    }
}

private struct IslandDiffGutter: View {
    let number: Int
    let colors: IslandDiffStyle.LineColors
    let width: CGFloat

    var body: some View {
        Text("\(number)")
            .foregroundStyle(colors.gutter)
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, 10)
    }
}

private struct IslandDiffMarker: View {
    let kind: PermissionDiffLine.Kind
    let colors: IslandDiffStyle.LineColors
    let width: CGFloat

    var body: some View {
        Text(IslandDiffRenderer.marker(for: kind))
            .foregroundStyle(colors.marker)
            .frame(width: width, alignment: .leading)
            .padding(.trailing, 4)
    }
}

/// Theme input for `IslandDiffRenderer`.  Colours are deliberately carried per
/// line kind; geometry and structural cells stay shared.
struct IslandDiffStyle {
    struct LineColors {
        let gutter: Color
        let marker: Color
        let content: Color
        let background: Color
    }

    struct Border {
        let color: Color
        let width: CGFloat
    }

    enum HeaderTitle: Equatable {
        case updatedCounts
        case haloFile(affectedPath: String?)
        case pouredFile(fileName: String?, hunk: String?)
    }

    /// An optional theme-specific header treatment. The structural renderer owns
    /// the icon and title while a theme may select filename copy, type, and rule.
    struct HeaderStyle {
        let title: HeaderTitle
        let font: Font
        let iconFont: Font
        let iconOpacity: Double
        let color: Color
        let background: Color
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let bottomBorder: Border?
    }

    /// A type-safe container choice that remains an `InsettableShape`, allowing
    /// the renderer to use the same shape for fill, `strokeBorder`, and clipping.
    enum ContainerShape: InsettableShape, Equatable {
        case rounded(cornerRadius: CGFloat, inset: CGFloat = 0)
        case chamfered(chamfer: CGFloat, inset: CGFloat = 0)

        func inset(by amount: CGFloat) -> ContainerShape {
            switch self {
            case let .rounded(cornerRadius, inset):
                .rounded(cornerRadius: cornerRadius, inset: inset + amount)
            case let .chamfered(chamfer, inset):
                .chamfered(chamfer: chamfer, inset: inset + amount)
            }
        }

        func path(in rect: CGRect) -> Path {
            switch self {
            case let .rounded(cornerRadius, inset):
                return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .inset(by: inset)
                    .path(in: rect)
            case let .chamfered(chamfer, inset):
                let insetRect = rect.insetBy(dx: inset, dy: inset)
                let corner = min(chamfer, min(insetRect.width, insetRect.height) / 2)
                var path = Path()
                path.move(to: CGPoint(x: insetRect.minX + corner, y: insetRect.minY))
                path.addLine(to: CGPoint(x: insetRect.maxX - corner, y: insetRect.minY))
                path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.minY + corner))
                path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.maxY - corner))
                path.addLine(to: CGPoint(x: insetRect.maxX - corner, y: insetRect.maxY))
                path.addLine(to: CGPoint(x: insetRect.minX + corner, y: insetRect.maxY))
                path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.maxY - corner))
                path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.minY + corner))
                path.closeSubpath()
                return path
            }
        }
    }

    /// The design values are inspectable separately from SwiftUI's opaque
    /// `Font`, which makes the 11.5pt regular mono contract unit-testable.
    struct Typography: Equatable {
        enum Weight: Equatable { case regular }
        enum Design: Equatable { case monospaced }

        let size: CGFloat
        let weight: Weight
        let design: Design
    }

    /// Neutral default type shared by the token-driven and Flight Deck styles.
    /// Theme-specific factories may still provide their own typography where
    /// their visual language requires it.
    static let sharedFont: Font = .system(size: 11.5, weight: .regular, design: .monospaced)
    static let sharedTypography = Typography(size: 11.5, weight: .regular, design: .monospaced)

    let gutterWidth: CGFloat
    let markerWidth: CGFloat
    let horizontalPadding: CGFloat
    let font: Font
    let typography: Typography
    let added: LineColors
    let removed: LineColors
    let context: LineColors
    let headerColor: Color
    let headerBackground: Color
    let containerBackground: Color
    let containerBorder: Border?
    let containerShape: ContainerShape
    let rowTrailingPadding: CGFloat?
    let scrollVerticalPadding: CGFloat?
    /// Rows a caller clamped away before handing the result to the renderer, so
    /// the "+N more lines" line renders inside the well over the clamped result.
    /// Defaults to 0, leaving every non-clamping caller byte-identical.
    let additionalHiddenLines: Int
    let header: HeaderStyle?

    init(
        gutterWidth: CGFloat,
        markerWidth: CGFloat,
        horizontalPadding: CGFloat,
        font: Font,
        typography: Typography,
        added: LineColors,
        removed: LineColors,
        context: LineColors,
        headerColor: Color,
        headerBackground: Color,
        containerBackground: Color,
        containerBorder: Border?,
        containerShape: ContainerShape,
        rowTrailingPadding: CGFloat? = nil,
        scrollVerticalPadding: CGFloat? = nil,
        additionalHiddenLines: Int = 0,
        header: HeaderStyle? = nil
    ) {
        self.gutterWidth = gutterWidth
        self.markerWidth = markerWidth
        self.horizontalPadding = horizontalPadding
        self.font = font
        self.typography = typography
        self.added = added
        self.removed = removed
        self.context = context
        self.headerColor = headerColor
        self.headerBackground = headerBackground
        self.containerBackground = containerBackground
        self.containerBorder = containerBorder
        self.containerShape = containerShape
        self.rowTrailingPadding = rowTrailingPadding
        self.scrollVerticalPadding = scrollVerticalPadding
        self.additionalHiddenLines = additionalHiddenLines
        self.header = header
    }

    func colors(for kind: PermissionDiffLine.Kind) -> LineColors {
        switch kind {
        case .added: added
        case .removed: removed
        case .unchanged: context
        }
    }

    /// The neutral shared style is suitable for the legacy token-driven card
    /// until its caller is deliberately migrated in a later Phase 7 slice.
    static func standard(tokens: IslandThemeTokens, containerShape: ContainerShape = .rounded(cornerRadius: 10)) -> Self {
        let paper = tokens.colors.paper
        return Self(
            gutterWidth: 26,
            markerWidth: 10,
            horizontalPadding: 8,
            font: sharedFont,
            typography: sharedTypography,
            added: LineColors(gutter: tokens.colors.statusCompleted.opacity(0.7), marker: tokens.colors.statusCompleted, content: paper.opacity(0.86), background: tokens.colors.statusCompleted.opacity(0.12)),
            removed: LineColors(gutter: tokens.colors.statusFailed.opacity(0.7), marker: tokens.colors.statusFailed, content: paper.opacity(0.86), background: tokens.colors.statusFailed.opacity(0.12)),
            context: LineColors(gutter: paper.opacity(0.3), marker: paper.opacity(0.3), content: paper.opacity(0.5), background: .clear),
            headerColor: paper.opacity(0.6),
            headerBackground: .clear,
            containerBackground: tokens.colors.surfaceInk.opacity(0.6),
            containerBorder: Border(color: .white.opacity(0.06), width: 1),
            containerShape: containerShape
        )
    }
}
