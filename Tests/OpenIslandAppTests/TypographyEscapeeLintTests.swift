import Foundation
import Testing

/// Phase 6 seed gate: preserve the current, intentionally classified inventory
/// while rejecting every newly introduced raw system-font construction.
struct TypographyEscapeeLintTests {
    @Test
    func islandSystemFontEscapeesMatchCommittedAllowlist() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let actual = try TypographyEscapeeLint.scan(repositoryRoot: root)
        let allowed = TypographyEscapeeLint.allowlist

        let unexpected = TypographyEscapeeLint.difference(actual, allowed)
        #expect(unexpected.isEmpty, "New raw system-font escapees must be added to a typography role instead.")

        let stale = TypographyEscapeeLint.difference(allowed, actual)
        #expect(stale.isEmpty, "Retire an allowlist entry when its raw system-font site is removed.")
    }

    @Test
    func newEscapeeIsRejectedByTheSeedAllowlist() throws {
        let escapee = try #require(
            TypographyEscapeeLint.matches(
                in: "Text(\"New\").font(.system(size: 99))",
                relativePath: "NewIslandView.swift"
            ).first
        )

        #expect(TypographyEscapeeLint.difference([escapee], []) == [escapee])
    }
}

private enum TypographyEscapeeLint {
    struct Match: Hashable {
        let path: String
        let occurrence: Int
        let sourceLine: String
    }

    private static let expression = try! NSRegularExpression(
        pattern: "(?:Font\\.)?\\.system\\s*\\(\\s*(?:size\\s*:|[0-9])"
    )

    static func scan(repositoryRoot: URL) throws -> [Match] {
        let islandDirectory = repositoryRoot.appending(path: "Sources/OpenIslandApp/Views/Island")
        let files = try FileManager.default.contentsOfDirectory(
            at: islandDirectory,
            includingPropertiesForKeys: nil
        )
        return try files
            .filter { $0.pathExtension == "swift" }
            .flatMap { file in
                try matches(
                    in: String(contentsOf: file, encoding: .utf8),
                    relativePath: file.lastPathComponent
                )
            }
    }

    static var allowlist: [Match] {
        TypographyEscapeeAllowlist.rows
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") }
            .compactMap { row in
                let fields = row.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
                guard fields.count == 4, let occurrence = Int(fields[2]) else { return nil }
                return Match(path: String(fields[0]), occurrence: occurrence, sourceLine: String(fields[3]))
            }
    }

    static func difference(_ candidates: [Match], _ baseline: [Match]) -> [Match] {
        var baselineCounts = Dictionary(grouping: baseline, by: { $0 }).mapValues(\.count)
        return candidates.filter { candidate in
            guard let count = baselineCounts[candidate], count > 0 else { return true }
            baselineCounts[candidate] = count - 1
            return false
        }
    }

    static func matches(in source: String, relativePath: String) -> [Match] {
        var results: [Match] = []
        source.enumerateLines { line, _ in
            let range = NSRange(line.startIndex..., in: line)
            let hits = expression.matches(in: line, range: range)
            results.append(contentsOf: hits.enumerated().map { index, _ in
                Match(path: relativePath, occurrence: index + 1, sourceLine: line.trimmingCharacters(in: .whitespaces))
            })
        }
        return results
    }
}
