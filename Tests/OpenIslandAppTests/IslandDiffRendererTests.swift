import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct IslandDiffRendererTests {
    @Test
    func markerIsPurelyDerivedFromLineKind() {
        #expect(IslandDiffRenderer.marker(for: .added) == "+")
        #expect(IslandDiffRenderer.marker(for: .removed) == "\u{2212}")
        #expect(IslandDiffRenderer.marker(for: .unchanged).isEmpty)
    }

    @Test
    func rowModelAlwaysCarriesGutterAndDedicatedMarker() {
        let result = PermissionDiffResult(lines: [
            PermissionDiffLine(kind: .unchanged, text: "+ source text is not a marker"),
            PermissionDiffLine(kind: .removed, text: "- source text is not a marker"),
            PermissionDiffLine(kind: .added, text: "plain replacement"),
        ], addedCount: 1, removedCount: 1)

        let rows = IslandDiffRenderer.rows(for: result)

        #expect(rows.map(\.gutter) == [1, 2, 2])
        #expect(rows.map(\.marker) == ["", "\u{2212}", "+"])
        #expect(rows.map(\.line.text) == ["+ source text is not a marker", "- source text is not a marker", "plain replacement"])
    }

    @Test
    func rowModelCapsAtFiveHundredLines() {
        let lines = (0..<IslandDiffRenderer.maxRenderedLines + 1).map {
            PermissionDiffLine(kind: .unchanged, text: "line \($0)")
        }
        let result = PermissionDiffResult(lines: lines, addedCount: 0, removedCount: 0)

        #expect(IslandDiffRenderer.rows(for: result).count == 500)
        #expect(IslandDiffRenderer.maxHeight == 180)
    }

    @Test
    func stylePinsSharedTypographyAndBothContainerShapes() {
        let standard = IslandDiffStyle.standard(tokens: .poured)
        let poured = IslandDiffStyle.poured(tokens: .poured, reduceTransparency: false)
        let flightDeck = IslandDiffStyle.flightDeck(tokens: .flightDeck, increasesContrast: false)

        #expect(standard.gutterWidth == 26)
        #expect(standard.markerWidth == 10)
        #expect(standard.typography == .init(size: 11.5, weight: .regular, design: .monospaced))
        #expect(standard.containerShape == .rounded(cornerRadius: 10))
        #expect(poured.gutterWidth == 26)
        #expect(poured.markerWidth == 10)
        #expect(poured.typography == .init(size: 11.5, weight: .regular, design: .monospaced))
        #expect(poured.containerShape == .rounded(cornerRadius: 10))
        #expect(poured.containerBorder?.width == 1)
        #expect(flightDeck.containerShape == .chamfered(chamfer: 5))
        #expect(flightDeck.containerShape.inset(by: 1) == .chamfered(chamfer: 5, inset: 1))
        #expect(flightDeck.gutterWidth == 26)
        #expect(flightDeck.markerWidth == 10)
        #expect(flightDeck.typography == .init(size: 11.5, weight: .regular, design: .monospaced))
        #expect(flightDeck.header?.title == .flightDeckUpdatedCounts)
        #expect(flightDeck.containerBorder?.width == 1)
    }

    @Test
    func sharedDiffTypographyIsThemeNeutral() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let renderer = try String(
            contentsOf: root.appending(path: "Sources/OpenIslandApp/Views/Island/IslandDiffRenderer.swift"),
            encoding: .utf8
        )

        #expect(renderer.contains("static let sharedFont: Font = .system(size: 11.5, weight: .regular, design: .monospaced)"))
        #expect(renderer.contains("static let sharedTypography = Typography(size: 11.5, weight: .regular, design: .monospaced)"))
        #expect(!renderer.contains("PouredType"))
    }

    @Test
    func haloStylePreservesTheE2GeometryAndFilenameHeader() {
        let halo = IslandDiffStyle.halo(
            tokens: .halo,
            increasesContrast: false,
            affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift"
        )

        #expect(halo.gutterWidth == 22)
        #expect(halo.markerWidth == 10)
        #expect(halo.typography == .init(size: 11.5, weight: .regular, design: .monospaced))
        #expect(halo.containerShape == .rounded(cornerRadius: 9))
        #expect(halo.containerBorder?.width == 1)
        #expect(halo.rowTrailingPadding == 11)
        #expect(halo.scrollVerticalPadding == 2)
        #expect(halo.header?.title == .haloFile(affectedPath: "Sources/OpenIslandApp/Views/SettingsView.swift"))
        #expect(halo.header?.horizontalPadding == 11)
        #expect(halo.header?.verticalPadding == 6)
        #expect(halo.header?.bottomBorder?.width == 1)
    }

    @Test
    func flightDeckSourceUsesTheSharedChamferedRendererAndRetainsOnlyD2LegacyCallers() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let islandDirectory = root.appending(path: "Sources/OpenIslandApp/Views/Island")
        let flightDeck = try String(
            contentsOf: islandDirectory.appending(path: "FlightDeckSessionRow.swift"),
            encoding: .utf8
        )
        let renderer = try String(
            contentsOf: islandDirectory.appending(path: "IslandDiffRenderer.swift"),
            encoding: .utf8
        )

        #expect(flightDeck.contains("IslandDiffRenderer("))
        #expect(flightDeck.contains("style: .flightDeck(tokens: tokens, increasesContrast: increasesContrast)"))
        #expect(!flightDeck.contains("PermissionDiffPreview(result: diffResult, lang: lang)"))
        let diffTail = try #require(
            flightDeck.components(separatedBy: "if let diffResult = permissionDiffResult {").dropFirst().first
        )
        let diffSection = try #require(
            diffTail.components(separatedBy: "if session.permissionRequest?.requiresTerminalApproval == true {").first
        )
        #expect(!diffSection.contains("RoundedRectangle"))
        #expect(!diffSection.contains(".background("))
        #expect(!diffSection.contains(".overlay("))
        #expect(renderer.contains("containerShape: .chamfered(chamfer: 5)"))
        #expect(renderer.contains("gutterWidth: 26"))
        #expect(renderer.contains("markerWidth: 10"))
        #expect(renderer.contains("FlightDeckText.caps(lang.t(\"approval.diffUpdated\"), lang: lang)"))

        let islandSources = try FileManager.default.contentsOfDirectory(
            at: islandDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        let legacyCandidates = islandSources + [
            root.appending(path: "Sources/OpenIslandApp/Views/IslandPanelView.swift")
        ]
        let callers = legacyCandidates
        .filter { url in
            (try? String(contentsOf: url, encoding: .utf8))?.contains("PermissionDiffPreview(") == true
        }
        .map(\.lastPathComponent)
        .sorted()

        #expect(callers == ["AnnualSessionRow.swift", "InstrumentSessionRow.swift", "IslandPanelView.swift"])
    }
}
