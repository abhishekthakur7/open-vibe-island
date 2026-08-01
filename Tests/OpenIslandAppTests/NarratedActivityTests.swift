import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-321 — the narrated activity presentation layer.
///
/// BRIEF §1.2: the shipped UI renders internal state ("Mcp Playwright Browser
/// Evaluate ×4", `$ source ~/.nvm/nvm…`). These tests pin the translation of
/// tool identifier + command preview into a human sentence.
struct NarratedActivityTests {

    // MARK: - The three BRIEF-named examples (AC #3)

    @Test
    func briefExampleEditingProducesFileBasename() {
        let narration = ActivityNarrator.narrate(
            toolName: "Edit",
            preview: "/Users/abhishek/Developer/open-vibe-island/Sources/OpenIslandApp/AppModel.swift"
        )

        #expect(narration?.verb == "Editing")
        #expect(narration?.object == "AppModel.swift")
        #expect(narration?.text == "Editing AppModel.swift")
    }

    @Test
    func briefExampleMCPBrowserEvaluateProducesSentence() {
        let narration = ActivityNarrator.narrate(toolName: "mcp__playwright__browser_evaluate")

        #expect(narration?.verb == "Evaluating")
        #expect(narration?.object == "in the browser")
        #expect(narration?.text == "Evaluating in the browser")
    }

    @Test
    func briefExampleBashProducesRunningCommand() {
        let narration = ActivityNarrator.narrate(toolName: "Bash", preview: "swift build")

        #expect(narration?.verb == "Running")
        #expect(narration?.object == "swift build")
        #expect(narration?.text == "Running swift build")
    }

    // MARK: - Verb map rows (AC #2) — one raw-input example each

    // MARK: - MCP identifiers (AC #2 · #4)

    @Test
    func mcpNarrationNeverLeaksTheRawIdentifier() {
        let identifiers = [
            "mcp__playwright__browser_evaluate",
            "Mcp Playwright Browser Evaluate",
            "mcp__serena__find_symbol",
            "mcp__canva__get-design",
            "mcp__acme__widget_wobble",
        ]

        for identifier in identifiers {
            let text = ActivityNarrator.narrate(toolName: identifier)?.text ?? ""
            #expect(!text.isEmpty, "\(identifier) narrated to nothing")
            #expect(!text.lowercased().contains("mcp"), "\(identifier) leaked the raw identifier: \(text)")
            #expect(!text.contains("__"), "\(identifier) leaked the raw identifier: \(text)")
        }
    }

    // MARK: - Unknown tools (AC #2 fallback row)

    // MARK: - Forbidden output shapes (AC #4)

    @Test
    func narrationNeverAppendsAnInvocationCount() {
        // The old UI's "×4" was invented precision (BRIEF §3). Nothing in the
        // narration layer can produce it.
        let narration = ActivityNarrator.narrate(
            toolName: "mcp__playwright__browser_evaluate",
            preview: "() => document.title"
        )

        #expect(narration?.text.contains("×") == false)
    }

    // MARK: - Truncation (AC #4 · #5)

    // MARK: - Session-level API (AC #1)

    @Test
    func sessionExposesNarratedActivityFromItsMetadata() {
        let session = AgentSession(
            id: "session-narrated-1",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            claudeMetadata: ClaudeSessionMetadata(
                currentTool: "Edit",
                currentToolInputPreview: "/Users/a/open-vibe-island/Sources/OpenIslandApp/AppModel.swift"
            )
        )

        #expect(session.narratedActivityLineText == "Editing AppModel.swift")
        #expect(session.narratedActivityLine?.verb == "Editing")
        #expect(session.narratedActivityLine?.object == "AppModel.swift")
    }

    // MARK: - Existing presentation is untouched (AC #7)

    @Test
    func existingSpotlightSurfacesKeepTheirShippedRendering() {
        let session = AgentSession(
            id: "session-narrated-4",
            title: "Claude · open-vibe-island",
            tool: .claudeCode,
            origin: .live,
            phase: .running,
            summary: "Working",
            updatedAt: Date.now,
            claudeMetadata: ClaudeSessionMetadata(
                currentTool: "Edit",
                currentToolInputPreview: "/Users/a/AppModel.swift"
            )
        )

        // Classic / Annual / Instrument still see the noun + raw preview.
        #expect(AgentSession.currentToolDisplayName(for: "Edit") == "Edit")
        #expect(session.displayCurrentToolName == "Edit")
        #expect(session.spotlightSecondaryText == "Running Edit")
        #expect(session.spotlightActivityLineText == "Edit /Users/a/AppModel.swift")
    }

    // MARK: - Localization (AC #6)

    @Test
    func everyVerbLocalizesInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            for verb in NarrationVerb.allCases {
                let resolved = manager.t(verb.localizationKey)
                #expect(resolved != verb.localizationKey, "\(verb.localizationKey) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
    }

    // MARK: - Gerund derivation
}
