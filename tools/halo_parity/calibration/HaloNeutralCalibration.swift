import AppKit
import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI

private enum NeutralCalibrationError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case displayUnavailable(UInt32)
    case invalidScale(CGFloat)
    case manifestEncoding

    var description: String {
        switch self {
        case let .invalidArgument(message):
            message
        case let .displayUnavailable(displayID):
            "No NSScreen matched display ID \(displayID)."
        case let .invalidScale(scale):
            "Neutral calibration requires a 2x screen; resolved scale was \(scale)."
        case .manifestEncoding:
            "Unable to encode the neutral calibration manifest."
        }
    }
}

private enum NeutralProfile: String, Codable {
    case notch = "notch-v1"
    case topBar = "top-bar-v1"

    var pointSize: CGSize {
        switch self {
        case .notch:
            CGSize(width: 540, height: 320)
        case .topBar:
            CGSize(width: 520, height: 320)
        }
    }
}

private enum NeutralMode: String, Codable {
    case `static`
    case manual
    case normal
    case reduced
}

private struct NeutralConfiguration {
    let profile: NeutralProfile
    let mode: NeutralMode
    let timeMilliseconds: Double
    let displayID: UInt32
    let manifestURL: URL
    let autoExitMilliseconds: Double?

    static func parse(arguments: [String]) throws -> NeutralConfiguration {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        guard let profileRaw = value(after: "--profile"),
              let profile = NeutralProfile(rawValue: profileRaw) else {
            throw NeutralCalibrationError.invalidArgument(
                "--profile must be notch-v1 or top-bar-v1"
            )
        }
        guard let modeRaw = value(after: "--mode"),
              let mode = NeutralMode(rawValue: modeRaw) else {
            throw NeutralCalibrationError.invalidArgument(
                "--mode must be static, manual, normal, or reduced"
            )
        }
        guard let displayRaw = value(after: "--display-id"),
              let displayID = UInt32(displayRaw) else {
            throw NeutralCalibrationError.invalidArgument(
                "--display-id must be an unsigned integer"
            )
        }
        guard let manifestRaw = value(after: "--manifest"),
              !manifestRaw.isEmpty else {
            throw NeutralCalibrationError.invalidArgument("--manifest is required")
        }
        let timeMilliseconds = value(after: "--time-ms").flatMap(Double.init) ?? 0
        guard timeMilliseconds.isFinite, timeMilliseconds >= 0 else {
            throw NeutralCalibrationError.invalidArgument(
                "--time-ms must be a finite nonnegative number"
            )
        }
        if mode != .manual, timeMilliseconds != 0 {
            throw NeutralCalibrationError.invalidArgument(
                "--time-ms is valid only with --mode manual"
            )
        }
        let autoExitMilliseconds = value(after: "--auto-exit-ms").flatMap(Double.init)
        if let autoExitMilliseconds,
           (!autoExitMilliseconds.isFinite || autoExitMilliseconds <= 0) {
            throw NeutralCalibrationError.invalidArgument(
                "--auto-exit-ms must be a finite positive number"
            )
        }
        return NeutralConfiguration(
            profile: profile,
            mode: mode,
            timeMilliseconds: timeMilliseconds,
            displayID: displayID,
            manifestURL: URL(fileURLWithPath: manifestRaw),
            autoExitMilliseconds: autoExitMilliseconds
        )
    }
}

private struct NeutralPalette {
    static let black = Color(red: 0, green: 0, blue: 0)
    static let dark = Color(red: 32 / 255, green: 32 / 255, blue: 32 / 255)
    static let gray = Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255)
    static let white = Color(red: 1, green: 1, blue: 1)
}

private struct NeutralCalibrationView: View {
    let configuration: NeutralConfiguration
    let monotonicOrigin: CFTimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: configuration.mode != .normal)) { _ in
            Canvas(rendersAsynchronously: false) { context, size in
                draw(context: &context, size: size, phase: phase)
            }
        }
        .frame(
            width: configuration.profile.pointSize.width,
            height: configuration.profile.pointSize.height
        )
        .background(NeutralPalette.black)
        .accessibilityIdentifier("neutral-calibration-v1")
    }

    private var phase: CGFloat {
        switch configuration.mode {
        case .static, .reduced:
            0
        case .manual:
            CGFloat((configuration.timeMilliseconds.truncatingRemainder(dividingBy: 1000)) / 1000)
        case .normal:
            CGFloat((CACurrentMediaTime() - monotonicOrigin).truncatingRemainder(dividingBy: 1))
        }
    }

    private func draw(
        context: inout GraphicsContext,
        size: CGSize,
        phase: CGFloat
    ) {
        let canvas = CGRect(origin: .zero, size: size)
        context.fill(Path(canvas), with: .color(NeutralPalette.black))
        context.stroke(
            Path(canvas.insetBy(dx: 0.5, dy: 0.5)),
            with: .color(NeutralPalette.gray),
            lineWidth: 1
        )

        let padding: CGFloat = 13
        let gap: CGFloat = 8
        let columnWidth = (size.width - (padding * 2) - gap) / 2
        let rowHeight = (size.height - (padding * 2) - (gap * 3)) / 4
        let identifiers = [
            "registration-grid",
            "solid-srgb-patches",
            "neutral-width-lines",
            "rounded-geometry",
            "alpha-gradient-stack",
            "neutral-bloom",
            "font-raster-boxes",
            "motion-track",
        ]

        for index in identifiers.indices {
            let column = index % 2
            let row = index / 2
            let rect = CGRect(
                x: padding + CGFloat(column) * (columnWidth + gap),
                y: padding + CGFloat(row) * (rowHeight + gap),
                width: columnWidth,
                height: rowHeight
            )
            drawPrimitiveFrame(
                context: &context,
                rect: rect,
                identifier: identifiers[index]
            )
            switch identifiers[index] {
            case "registration-grid":
                drawRegistrationGrid(context: &context, rect: rect)
            case "solid-srgb-patches":
                drawSolidPatches(context: &context, rect: rect)
            case "neutral-width-lines":
                drawWidthLines(context: &context, rect: rect)
            case "rounded-geometry":
                drawRoundedGeometry(context: &context, rect: rect)
            case "alpha-gradient-stack":
                drawAlphaStack(context: &context, rect: rect)
            case "neutral-bloom":
                drawNeutralBloom(context: &context, rect: rect)
            case "font-raster-boxes":
                drawFontBoxes(context: &context, rect: rect)
            case "motion-track":
                drawMotionTrack(context: &context, rect: rect, phase: phase)
            default:
                break
            }
        }
    }

    private func drawPrimitiveFrame(
        context: inout GraphicsContext,
        rect: CGRect,
        identifier: String
    ) {
        context.fill(Path(rect), with: .color(NeutralPalette.black))
        context.stroke(
            Path(rect.insetBy(dx: 0.5, dy: 0.5)),
            with: .color(NeutralPalette.dark),
            lineWidth: 1
        )
        let label = context.resolve(
            Text(identifier)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(NeutralPalette.gray)
        )
        context.draw(
            label,
            at: CGPoint(x: rect.maxX - 4, y: rect.maxY - 3),
            anchor: .bottomTrailing
        )
    }

    private func drawRegistrationGrid(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            var grid = Path()
            var x = rect.minX
            while x <= rect.maxX {
                grid.move(to: CGPoint(x: x + 0.5, y: rect.minY))
                grid.addLine(to: CGPoint(x: x + 0.5, y: rect.maxY))
                x += 16
            }
            var y = rect.minY
            while y <= rect.maxY {
                grid.move(to: CGPoint(x: rect.minX, y: y + 0.5))
                grid.addLine(to: CGPoint(x: rect.maxX, y: y + 0.5))
                y += 16
            }
            layer.stroke(grid, with: .color(NeutralPalette.gray), lineWidth: 1)
            for origin in [
                CGPoint(x: rect.minX + 8, y: rect.minY + 8),
                CGPoint(x: rect.maxX - 13, y: rect.minY + 8),
                CGPoint(x: rect.minX + 8, y: rect.maxY - 13),
                CGPoint(x: rect.maxX - 13, y: rect.maxY - 13),
            ] {
                let marker = CGRect(origin: origin, size: CGSize(width: 5, height: 5))
                layer.stroke(
                    Path(marker.insetBy(dx: 0.5, dy: 0.5)),
                    with: .color(NeutralPalette.white),
                    lineWidth: 1
                )
            }
        }
    }

    private func drawSolidPatches(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let colors = [
            NeutralPalette.black,
            NeutralPalette.dark,
            NeutralPalette.gray,
            NeutralPalette.white,
        ]
        let width = rect.width / 4
        for index in colors.indices {
            context.fill(
                Path(
                    CGRect(
                        x: rect.minX + CGFloat(index) * width,
                        y: rect.minY,
                        width: width,
                        height: rect.height
                    )
                ),
                with: .color(colors[index])
            )
        }
    }

    private func drawWidthLines(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let widths: [CGFloat] = [1, 1.5, 2]
        let total = widths.reduce(0, +) + 24
        var y = rect.midY - total / 2
        for width in widths {
            y += width / 2
            var line = Path()
            line.move(to: CGPoint(x: rect.minX + 12, y: y))
            line.addLine(to: CGPoint(x: rect.maxX - 12, y: y))
            context.stroke(line, with: .color(NeutralPalette.white), lineWidth: width)
            y += width / 2 + 12
        }
    }

    private func drawRoundedGeometry(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let radii: [CGFloat] = [8, 19, 28]
        let centers = evenlySpacedCenters(count: radii.count, in: rect)
        for (index, centerX) in centers.enumerated() {
            let shape = CGRect(x: centerX - 21, y: rect.midY - 21, width: 42, height: 42)
            let path = Path(
                roundedRect: shape,
                cornerRadius: radii[index]
            )
            context.fill(path, with: .color(NeutralPalette.dark))
            context.stroke(path, with: .color(NeutralPalette.white), lineWidth: 1)
        }
    }

    private func drawAlphaStack(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let alphas: [Double] = [0.08, 0.16, 0.5, 1]
        let width = rect.width / 4
        for index in alphas.indices {
            context.fill(
                Path(
                    CGRect(
                        x: rect.minX + CGFloat(index) * width,
                        y: rect.minY,
                        width: width,
                        height: rect.height
                    )
                ),
                with: .color(NeutralPalette.white.opacity(alphas[index]))
            )
        }
    }

    private func drawNeutralBloom(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let radii: [CGFloat] = [2, 4, 8]
        let centers = evenlySpacedCenters(count: radii.count, in: rect)
        for (index, centerX) in centers.enumerated() {
            let circle = Path(
                ellipseIn: CGRect(x: centerX - 7, y: rect.midY - 7, width: 14, height: 14)
            )
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .white, radius: radii[index]))
                layer.fill(circle, with: .color(NeutralPalette.white))
            }
        }
    }

    private func drawFontBoxes(
        context: inout GraphicsContext,
        rect: CGRect
    ) {
        let sizes: [CGFloat] = [10, 11, 12, 13]
        let leftX = rect.minX + 8
        let rightX = rect.midX + 4
        let lineHeight = (rect.height - 16) / 4
        for (index, size) in sizes.enumerated() {
            let y = rect.minY + 8 + CGFloat(index) * lineHeight
            let sans = context.resolve(
                Text("Ag 012345")
                    .font(.system(size: size))
                    .foregroundStyle(NeutralPalette.white)
            )
            let mono = context.resolve(
                Text("Ag 012345")
                    .font(.system(size: size, design: .monospaced))
                    .foregroundStyle(NeutralPalette.white)
            )
            context.draw(sans, at: CGPoint(x: leftX, y: y), anchor: .topLeading)
            context.draw(mono, at: CGPoint(x: rightX, y: y), anchor: .topLeading)
        }
    }

    private func drawMotionTrack(
        context: inout GraphicsContext,
        rect: CGRect,
        phase: CGFloat
    ) {
        var track = Path()
        track.move(to: CGPoint(x: rect.minX + 14, y: rect.minY + 31.5))
        track.addLine(to: CGPoint(x: rect.minX + 134, y: rect.minY + 31.5))
        context.stroke(track, with: .color(NeutralPalette.gray), lineWidth: 1)
        let marker = CGRect(
            x: rect.minX + 14 + phase * 120,
            y: rect.minY + 25,
            width: 13,
            height: 13
        )
        context.fill(Path(marker), with: .color(NeutralPalette.white))
    }

    private func evenlySpacedCenters(count: Int, in rect: CGRect) -> [CGFloat] {
        let step = rect.width / CGFloat(count)
        return (0..<count).map { rect.minX + step * (CGFloat($0) + 0.5) }
    }
}

@MainActor
private final class NeutralCalibrationApplication {
    private let configuration: NeutralConfiguration
    private let monotonicOrigin = CACurrentMediaTime()
    private var panel: NSPanel?

    init(configuration: NeutralConfiguration) {
        self.configuration = configuration
    }

    func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == configuration.displayID
        }) else {
            throw NeutralCalibrationError.displayUnavailable(configuration.displayID)
        }
        guard screen.backingScaleFactor == 2 else {
            throw NeutralCalibrationError.invalidScale(screen.backingScaleFactor)
        }

        let pointSize = configuration.profile.pointSize
        let frame = NSRect(
            x: screen.frame.midX - pointSize.width / 2,
            y: screen.frame.maxY - pointSize.height,
            width: pointSize.width,
            height: pointSize.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.title = "Neutral calibration \(configuration.profile.rawValue)"
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.level = .floating
        panel.sharingType = .readOnly
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentView = NSHostingView(
            rootView: NeutralCalibrationView(
                configuration: configuration,
                monotonicOrigin: monotonicOrigin
            )
        )
        panel.orderFrontRegardless()
        self.panel = panel
        try writeManifest(panel: panel, screen: screen)

        if let autoExitMilliseconds = configuration.autoExitMilliseconds {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + autoExitMilliseconds / 1000
            ) {
                NSApp.terminate(nil)
            }
        }
        app.run()
    }

    private func writeManifest(panel: NSPanel, screen: NSScreen) throws {
        let displayID = configuration.displayID
        let displayMode = CGDisplayCopyDisplayMode(displayID)
        let value: [String: Any] = [
            "schemaVersion": "1.0.0",
            "suiteId": "halo-neutral-calibration-v1",
            "contentRole": "neutral-calibration",
            "renderer": "native-swiftui-calibration",
            "profileId": configuration.profile.rawValue,
            "mode": configuration.mode.rawValue,
            "timeMilliseconds": configuration.timeMilliseconds,
            "process": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "bundleId": Bundle.main.bundleIdentifier ?? "",
                "executablePath": Bundle.main.executablePath ?? CommandLine.arguments[0],
            ],
            "window": [
                "cgWindowId": panel.windowNumber,
                "title": panel.title,
                "pointSize": [
                    "width": panel.frame.width,
                    "height": panel.frame.height,
                ],
                "layer": Int(panel.level.rawValue),
            ],
            "display": [
                "displayId": displayID,
                "localizedName": screen.localizedName,
                "backingScale": screen.backingScaleFactor,
                "framePoints": [
                    "width": screen.frame.width,
                    "height": screen.frame.height,
                ],
                "nativePixels": [
                    "width": displayMode?.pixelWidth ?? CGDisplayPixelsWide(displayID),
                    "height": displayMode?.pixelHeight ?? CGDisplayPixelsHigh(displayID),
                ],
                "vendorId": CGDisplayVendorNumber(displayID),
                "productId": CGDisplayModelNumber(displayID),
                "serialNumber": CGDisplaySerialNumber(displayID),
            ],
            "mapping": [
                "swiftUiPointToDevicePixel": 2,
                "expectedPixelSize": [
                    "width": Int(configuration.profile.pointSize.width * 2),
                    "height": Int(configuration.profile.pointSize.height * 2),
                ],
            ],
            "clock": [
                "mode": configuration.mode == .normal
                    ? "production-monotonic"
                    : "diagnostic-static-or-manual",
                "monotonicOriginSeconds": monotonicOrigin,
            ],
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "haloSourceHashes": [],
        ]
        guard JSONSerialization.isValidJSONObject(value) else {
            throw NeutralCalibrationError.manifestEncoding
        }
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: configuration.manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: configuration.manifestURL, options: .atomic)
    }
}

@main
private struct HaloNeutralCalibration {
    @MainActor
    static func main() {
        do {
            let configuration = try NeutralConfiguration.parse(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            try NeutralCalibrationApplication(configuration: configuration).run()
        } catch {
            FileHandle.standardError.write(
                Data("halo-neutral-calibration: \(error)\n".utf8)
            )
            Foundation.exit(2)
        }
    }
}
