import SwiftUI
import Testing
@testable import OpenIslandApp

/// AB-328 (draft T10) — the pure ``ShellCommandTokenizer`` behind the redesign's
/// syntax-highlighted permission hero.
///
/// Two kinds of assertions live here:
///
/// - **Exact-output** unit tests that pin the tokenization of the three spec
///   commands and the classification edge cases, so a regression in the rules
///   is a red test rather than a subtle colour shift in the UI.
/// - A **property** test that hammers the tokenizer with seeded pseudo-random
///   inputs and asserts the totality invariant: the spans always tile the whole
///   input with no gaps, no overlaps, and reassemble to the exact string.
struct ShellCommandTokenizerTests {

    // MARK: - Helpers

    private typealias Kind = ShellCommandTokenizer.Kind

    /// `(text, kind)` pairs — the readable form of a tokenization.
    private func tokens(_ command: String) -> [(text: String, kind: Kind)] {
        ShellCommandTokenizer.labeledTokens(command)
    }

    private func expectTokens(
        _ command: String,
        _ expected: [(String, Kind)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let actual = tokens(command)
        #expect(actual.count == expected.count, "token count for \(command.debugDescription)", sourceLocation: sourceLocation)
        for (a, e) in zip(actual, expected) {
            #expect(a.text == e.0, "text in \(command.debugDescription)", sourceLocation: sourceLocation)
            #expect(a.kind == e.1, "kind for \(a.text.debugDescription) in \(command.debugDescription)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Spec commands (exact output)

    /// Spec #1. `swift`=command, `build`=subcommand, `-c`/`--product`=flags, and
    /// the flag *values* (`release`, `OpenIslandHooks`) are deliberately plain —
    /// the rules do not model flag arity.
    @Test
    func specCommandSwiftBuild() {
        expectTokens(
            "swift build -c release --product OpenIslandHooks",
            [
                ("swift", .command),
                (" ", .plain),
                ("build", .subcommand),
                (" ", .plain),
                ("-c", .flag),
                (" ", .plain),
                ("release", .plain),
                (" ", .plain),
                ("--product", .flag),
                (" ", .plain),
                ("OpenIslandHooks", .plain),
            ]
        )
    }

    /// Spec #2. The quoted `"fetch("` is a single string token (its `(` never
    /// splits it), and `packages/ui/src` is a path by virtue of the `/`.
    @Test
    func specCommandRtkGrep() {
        expectTokens(
            #"rtk grep -rn "fetch(" packages/ui/src"#,
            [
                ("rtk", .command),
                (" ", .plain),
                ("grep", .subcommand),
                (" ", .plain),
                ("-rn", .flag),
                (" ", .plain),
                (#""fetch(""#, .string),
                (" ", .plain),
                ("packages/ui/src", .path),
            ]
        )
    }

    /// Spec #3. A bare URL preview. Decision: a URL is a ``Kind/path`` (it
    /// contains `/`), and the structural path rule outranks "first word =
    /// command", so the whole URL is one path span — no invented `$` prompt.
    @Test
    func specCommandBareURLIsPath() {
        expectTokens(
            "https://github.com/farouqaldori/claude-island",
            [
                ("https://github.com/farouqaldori/claude-island", .path),
            ]
        )
    }

    // MARK: - Classification edge cases

    @Test
    func subcommandRequiresACommandInFront() {
        // Word 0 is a path (URL), so word 1 is *not* auto-promoted to subcommand.
        expectTokens(
            "https://x.test/y run",
            [
                ("https://x.test/y", .path),
                (" ", .plain),
                ("run", .plain),
            ]
        )
    }

    @Test
    func flagBeatsPathWhenTokenHasBothDashAndSlash() {
        expectTokens(
            "cc -I/usr/include",
            [
                ("cc", .command),
                (" ", .plain),
                ("-I/usr/include", .flag),
            ]
        )
    }

    @Test
    func quotedArgumentWithInternalSpacesStaysOneToken() {
        expectTokens(
            #"send --msg="hi there" now"#,
            [
                ("send", .command),
                (" ", .plain),
                (#"--msg="hi there""#, .flag),
                (" ", .plain),
                ("now", .plain),
            ]
        )
    }

    // MARK: - AttributedString builder

    // MARK: - Property: totality (seeded, deterministic)

    /// The core invariant: for *any* input the spans tile the whole string.
    /// Reassembling their slices equals the input, they start at `startIndex`,
    /// end at `endIndex`, abut with no gap or overlap, and none is empty.
    @Test
    func spansAlwaysTileTheInputForRandomStrings() {
        var rng = SplitMix64(seed: 0xA1B2_C3D4_E5F6_0718)

        // A stress alphabet: letters, digits, the token-shaping punctuation
        // (dash, slash, dot, both quotes), whitespace incl. tab/newline, plus
        // multi-scalar graphemes (emoji, combining, CJK) to exercise indexing.
        let alphabet: [Character] = Array("abcXYZ019 \t\n-/.\"'=:_") + ["🎉", "🚀", "é", "汉", "👩‍💻"]

        for iteration in 0..<600 {
            let length = Int(rng.next() % 42)
            var input = ""
            input.reserveCapacity(length)
            for _ in 0..<length {
                input.append(alphabet[Int(rng.next() % UInt64(alphabet.count))])
            }
            assertTiling(input, iteration: iteration)
        }

        // Explicit adversarial inputs on top of the random sweep.
        let edgeCases: [String] = [
            "",
            " ",
            "   \t\n ",
            "🎉🚀👩‍💻",
            #"echo "unterminated"#,
            "'",
            "\"",
            "--",
            "-",
            "/",
            "a/b/c",
            String(repeating: "swift build -c release ", count: 500), // ~10.5k chars
            String(repeating: "🚀", count: 4000),
            #""a b c" 'd e f' g/h/i --flag=1"#,
        ]
        for (index, input) in edgeCases.enumerated() {
            assertTiling(input, iteration: 10_000 + index)
        }
    }

    private func assertTiling(
        _ input: String,
        iteration: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let spans = ShellCommandTokenizer.tokenize(input)

        // Reassembly equals the input (covers "no gaps" + "no lost bytes").
        let reassembled = spans.map { String(input[$0.range]) }.joined()
        #expect(reassembled == input, "reassembly mismatch @\(iteration)", sourceLocation: sourceLocation)

        if input.isEmpty {
            #expect(spans.isEmpty, "empty input must yield no spans @\(iteration)", sourceLocation: sourceLocation)
            return
        }

        #expect(spans.first?.range.lowerBound == input.startIndex, "must start at startIndex @\(iteration)", sourceLocation: sourceLocation)
        #expect(spans.last?.range.upperBound == input.endIndex, "must end at endIndex @\(iteration)", sourceLocation: sourceLocation)

        for span in spans {
            #expect(span.range.lowerBound < span.range.upperBound, "no empty span @\(iteration)", sourceLocation: sourceLocation)
        }
        for pair in zip(spans, spans.dropFirst()) {
            #expect(pair.0.range.upperBound == pair.1.range.lowerBound, "no gap/overlap @\(iteration)", sourceLocation: sourceLocation)
        }
    }
}

/// A tiny deterministic PRNG (SplitMix64) so the property test is reproducible
/// across machines and runs — no dependency on `SystemRandomNumberGenerator`.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
