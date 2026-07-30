import AppKit
import CoreMedia
import CoreGraphics
import CryptoKit
import Foundation
import ScreenCaptureKit

private enum CaptureError: Error, CustomStringConvertible {
    case usage(String)
    case windowNotFound(CGWindowID)
    case windowNotOnScreen(CGWindowID)
    case invalidCrop(String)
    case pngEncodingFailed
    case invalidMotion(String)
    case authenticity(String)
    case stream(String)

    var description: String {
        switch self {
        case let .usage(message): message
        case let .windowNotFound(id): "No WindowServer window matched CGWindowID \(id)."
        case let .windowNotOnScreen(id): "CGWindowID \(id) is not currently on screen."
        case let .invalidCrop(message): "Invalid live-window crop: \(message)"
        case .pngEncodingFailed: "Unable to encode ScreenCaptureKit image as PNG."
        case let .invalidMotion(message): "Invalid motion capture: \(message)"
        case let .authenticity(message): "Motion capture authenticity check failed: \(message)"
        case let .stream(message): "ScreenCaptureKit stream failed: \(message)"
        }
    }
}

private struct WindowRecord: Codable {
    let cgWindowId: UInt32
    let ownerPid: Int32?
    let ownerBundleId: String?
    let ownerName: String?
    let title: String?
    let bounds: RectRecord
    let layer: Int
    let isOnScreen: Bool
}

private struct RectRecord: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

private struct ListResult: Encodable {
    let schemaVersion = "1.0.0"
    let captureAPI = "ScreenCaptureKit"
    let screenRecordingPermission: Bool
    let windows: [WindowRecord]
}

private struct CaptureResult: Encodable {
    let schemaVersion = "1.0.0"
    let captureAPI = "ScreenCaptureKit"
    let captureMode = "live-window"
    let output: String
    let pixelWidth: Int
    let pixelHeight: Int
    let sourceRect: RectRecord
    let window: WindowRecord
    let captureTiming: CaptureTimingRecord
}

private struct CaptureTimingRecord: Encodable {
    let startedAt: String
    let completedAt: String
    let monotonicStartNanoseconds: String
    let monotonicEndNanoseconds: String
    let durationMilliseconds: Double
}

private struct DisplayRecord: Codable, Equatable {
    let displayId: UInt32
    let localizedName: String
    let framePoints: RectRecord
    let backingScale: Double
    let pixelWidth: Int
    let pixelHeight: Int
}

private struct MotionFrameRecord: Encodable {
    let frameIndex: Int
    let file: String
    let pixelFormat: String
    let pixelWidth: Int
    let pixelHeight: Int
    let bytesPerRow: Int
    let sha256: String
    let duplicate: Bool
    let ptsValue: String
    let ptsTimescale: Int32
    let ptsSeconds: Double
    let callbackMonotonicNanoseconds: String
    let observedIntervalSeconds: Double?
    let expectedIntervalSeconds: Double
    let intervalErrorSeconds: Double?
    let attachmentStatus: String
    let attachmentDisplayTime: String?
    let attachmentScaleFactor: Double?
    let attachmentContentScale: Double?
    let attachmentContentRect: RectRecord
    let attachmentDirtyRects: [RectRecord]
}

private struct DroppedFrameRecord: Encodable {
    let signal: String
    let afterFrameIndex: Int?
    let count: Int
    let reason: String
    let attachmentStatus: String?
    let ptsValue: String?
    let ptsTimescale: Int32?
    let ptsSeconds: Double?
}

private struct JitterRecord: Encodable {
    let sampleCount: Int
    let expectedIntervalSeconds: Double
    let meanObservedIntervalSeconds: Double?
    let minimumObservedIntervalSeconds: Double?
    let maximumObservedIntervalSeconds: Double?
    let standardDeviationSeconds: Double?
    let p95AbsoluteErrorSeconds: Double?
    let effectiveFramesPerSecond: Double?
}

private struct EventFrameZeroRecord: Encodable {
    let callerBinding: String
    let frameIndex: Int
    let ptsSeconds: Double
    let callbackMonotonicNanoseconds: String
    let basis: String
}

private struct MotionResult: Encodable {
    let schemaVersion = "1.0.0"
    let captureAPI = "ScreenCaptureKit"
    let captureMode = "live-window-motion"
    let storageEncoding = "raw-packed-bgra8"
    let hostMonotonicClock = "DispatchTime.uptimeNanoseconds"
    let outputDirectory: String
    let manifest: String
    let nominalFramesPerSecond: Int
    let requestedDurationSeconds: Double
    let actualPTSRangeSeconds: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let sourceRect: RectRecord
    let scale: Double
    let window: WindowRecord
    let display: DisplayRecord
    let expectedOwnerPid: Int32
    let expectedOwnerBundleId: String
    let captureTiming: CaptureTimingRecord
    let eventFrameZero: EventFrameZeroRecord
    let frames: [MotionFrameRecord]
    let droppedFrames: [DroppedFrameRecord]
    let duplicateFrameCount: Int
    let droppedFrameCount: Int
    let inferredDroppedFrameCount: Int
    let nonCompleteAttachmentCount: Int
    let jitter: JitterRecord
}

private final class MotionCollector: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let outputDirectory: URL
    private let expectedWidth: Int
    private let expectedHeight: Int
    private let expectedInterval = 1.0 / 60.0
    private let lock = NSLock()
    private var records: [MotionFrameRecord] = []
    private var drops: [DroppedFrameRecord] = []
    private var failure: Error?
    private var previousPTS: CMTime?
    private var previousHash: String?
    private var isSealed = false

    init(outputDirectory: URL, expectedWidth: Int, expectedHeight: Int) {
        self.outputDirectory = outputDirectory
        self.expectedWidth = expectedWidth
        self.expectedHeight = expectedHeight
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else {
            fail(CaptureError.stream("received a non-screen stream output"))
            return
        }
        lock.lock()
        defer { lock.unlock() }
        guard !isSealed, failure == nil else { return }
        do {
            try consume(sampleBuffer)
        } catch {
            failure = error
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fail(CaptureError.stream(error.localizedDescription))
    }

    func seal() throws -> (frames: [MotionFrameRecord], drops: [DroppedFrameRecord]) {
        lock.lock()
        defer { lock.unlock() }
        isSealed = true
        if let failure {
            throw failure
        }
        guard !records.isEmpty else {
            throw CaptureError.invalidMotion("no complete frames were delivered")
        }
        return (records, drops)
    }

    private func fail(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        if !isSealed, failure == nil {
            failure = error
        }
    }

    private func consume(_ sampleBuffer: CMSampleBuffer) throws {
        guard CMSampleBufferIsValid(sampleBuffer) else {
            throw CaptureError.stream("received an invalid sample buffer")
        }
        guard let attachmentArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentArray.first,
              let statusNumber = attachments[.status] as? NSNumber,
              let status = SCFrameStatus(rawValue: statusNumber.intValue) else {
            throw CaptureError.stream("frame is missing ScreenCaptureKit status attachments")
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid, !pts.isIndefinite, pts.timescale > 0 else {
            throw CaptureError.stream("frame is missing a finite CMSampleBuffer PTS")
        }
        let ptsSeconds = CMTimeGetSeconds(pts)
        guard ptsSeconds.isFinite else {
            throw CaptureError.stream("frame PTS is not finite")
        }
        guard status == .complete else {
            let reason = "ScreenCaptureKit attachment status \(statusName(status))"
            if status == .blank || status == .stopped {
                throw CaptureError.stream(
                    "\(reason); refusing non-window or unavailable-window content"
                )
            }
            drops.append(
                DroppedFrameRecord(
                    signal: "screen-capture-kit-attachment",
                    afterFrameIndex: records.last?.frameIndex,
                    count: 1,
                    reason: reason,
                    attachmentStatus: statusName(status),
                    ptsValue: String(pts.value),
                    ptsTimescale: pts.timescale,
                    ptsSeconds: ptsSeconds
                )
            )
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw CaptureError.stream("complete screen frame has no image buffer")
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width == expectedWidth, height == expectedHeight else {
            throw CaptureError.stream(
                "wrong crop size \(width)x\(height); expected \(expectedWidth)x\(expectedHeight)"
            )
        }
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw CaptureError.stream("frame pixel format is not 32-bit BGRA")
        }
        if let previousPTS {
            guard CMTimeCompare(pts, previousPTS) > 0 else {
                throw CaptureError.stream("frame PTS is not strictly monotonic")
            }
        }
        guard let contentRectValue = attachments[.contentRect] else {
            throw CaptureError.stream("frame is missing the contentRect attachment")
        }
        guard let contentRectDictionary = contentRectValue as? NSDictionary,
              let contentRect = CGRect(
                dictionaryRepresentation: contentRectDictionary as CFDictionary
              ),
              contentRect.width > 0,
              contentRect.height > 0 else {
            throw CaptureError.stream("frame contentRect attachment is invalid")
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CaptureError.stream("frame pixel buffer has no readable base address")
        }
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let packedBytesPerRow = width * 4
        var packed = Data(capacity: packedBytesPerRow * height)
        for row in 0..<height {
            packed.append(
                baseAddress.advanced(by: row * sourceBytesPerRow)
                    .assumingMemoryBound(to: UInt8.self),
                count: packedBytesPerRow
            )
        }
        let hash = SHA256.hash(data: packed).map { String(format: "%02x", $0) }.joined()
        let index = records.count
        let filename = String(format: "frame-%06d.bgra", index)
        try packed.write(to: outputDirectory.appendingPathComponent(filename), options: .atomic)
        let observed = previousPTS.map { CMTimeGetSeconds(CMTimeSubtract(pts, $0)) }
        if let observed {
            let inferred = max(0, Int((observed / expectedInterval).rounded()) - 1)
            if inferred > 0 {
                drops.append(
                    DroppedFrameRecord(
                        signal: "pts-gap",
                        afterFrameIndex: index - 1,
                        count: inferred,
                        reason: "PTS gap exceeded the nominal 60 fps interval",
                        attachmentStatus: statusName(status),
                        ptsValue: String(pts.value),
                        ptsTimescale: pts.timescale,
                        ptsSeconds: ptsSeconds
                    )
                )
            }
        }
        let dirtyRects = dirtyRectRecords(attachments[.dirtyRects])
        let record = MotionFrameRecord(
            frameIndex: index,
            file: filename,
            pixelFormat: "BGRA8",
            pixelWidth: width,
            pixelHeight: height,
            bytesPerRow: packedBytesPerRow,
            sha256: hash,
            duplicate: previousHash == hash,
            ptsValue: String(pts.value),
            ptsTimescale: pts.timescale,
            ptsSeconds: ptsSeconds,
            callbackMonotonicNanoseconds: String(DispatchTime.now().uptimeNanoseconds),
            observedIntervalSeconds: observed,
            expectedIntervalSeconds: expectedInterval,
            intervalErrorSeconds: observed.map { $0 - expectedInterval },
            attachmentStatus: statusName(status),
            attachmentDisplayTime: (attachments[.displayTime] as? NSNumber)?.stringValue,
            attachmentScaleFactor: (attachments[.scaleFactor] as? NSNumber)?.doubleValue,
            attachmentContentScale: (attachments[.contentScale] as? NSNumber)?.doubleValue,
            attachmentContentRect: rectRecord(contentRect),
            attachmentDirtyRects: dirtyRects
        )
        records.append(record)
        previousPTS = pts
        previousHash = hash
    }

    private func statusName(_ status: SCFrameStatus) -> String {
        switch status {
        case .complete: "complete"
        case .idle: "idle"
        case .blank: "blank"
        case .suspended: "suspended"
        case .started: "started"
        case .stopped: "stopped"
        @unknown default: "unknown-\(status.rawValue)"
        }
    }

    private func rectRecord(_ rect: CGRect) -> RectRecord {
        RectRecord(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    private func dirtyRectRecords(_ value: Any?) -> [RectRecord] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { item in
            if let rect = item as? CGRect {
                return rectRecord(rect)
            }
            if let dictionary = item as? NSDictionary,
               let rect = CGRect(
                   dictionaryRepresentation: dictionary as CFDictionary
               ) {
                return rectRecord(rect)
            }
            if let value = item as? NSValue {
                return rectRecord(value.rectValue)
            }
            return nil
        }
    }
}

@main
struct HaloWindowCapture {
    static func main() async {
        do {
            // SCScreenshotManager reaches CoreGraphics image services that
            // require a GUI process connection. Initializing NSApplication on
            // the main actor establishes it before any capture request.
            await MainActor.run {
                _ = NSApplication.shared
            }
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard let command = arguments.first else {
                throw CaptureError.usage(Self.usage)
            }
            if arguments.dropFirst().contains("--help")
                || arguments.dropFirst().contains("-h") {
                FileHandle.standardOutput.write(Data("\(Self.usage)\n".utf8))
                return
            }
            switch command {
            case "--help", "-h", "help":
                FileHandle.standardOutput.write(Data("\(Self.usage)\n".utf8))
            case "permission":
                try emit(["screenRecordingPermission": CGPreflightScreenCaptureAccess()])
            case "list":
                try await listWindows()
            case "capture":
                try await capture(arguments: Array(arguments.dropFirst()))
            case "motion":
                try await motion(arguments: Array(arguments.dropFirst()))
            default:
                throw CaptureError.usage(Self.usage)
            }
        } catch {
            FileHandle.standardError.write(
                Data("halo-window-capture: \(error)\n".utf8)
            )
            Foundation.exit(2)
        }
    }

    private static var usage: String {
        """
        Usage:
          halo-window-capture permission
          halo-window-capture list [--bundle-id ID] [--pid PID]
          halo-window-capture capture --window-id ID --output FILE.png [--scale 2]
            [--crop-x X --crop-y Y --crop-width W --crop-height H]
          halo-window-capture motion --window-id ID --output DIRECTORY
            --duration-seconds SECONDS --event-frame-zero CALLER_BINDING
            --expected-pid PID --expected-bundle-id ID [--scale 2]
            [--crop-x X --crop-y Y --crop-width W --crop-height H]

        Capture is restricted to one explicit on-screen WindowServer window.
        Motion writes lossless packed BGRA frames plus motion.json at nominal 60 fps.
        """
    }

    private static func shareableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        return content.windows
    }

    private static func listWindows() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst(2))
        let bundleId = value(after: "--bundle-id", in: arguments)
        let pid = value(after: "--pid", in: arguments).flatMap(Int32.init)
        let windows = try await shareableWindows()
            .filter { window in
                guard window.isOnScreen else { return false }
                if let bundleId,
                   window.owningApplication?.bundleIdentifier != bundleId {
                    return false
                }
                if let pid,
                   window.owningApplication?.processID != pid {
                    return false
                }
                return true
            }
            .map(record(for:))
            .sorted { lhs, rhs in lhs.cgWindowId < rhs.cgWindowId }
        try emit(
            ListResult(
                screenRecordingPermission: CGPreflightScreenCaptureAccess(),
                windows: windows
            )
        )
    }

    private static func capture(arguments: [String]) async throws {
        guard let rawWindowId = value(after: "--window-id", in: arguments),
              let windowId = UInt32(rawWindowId) else {
            throw CaptureError.usage("--window-id is required.\n\(usage)")
        }
        guard let outputValue = value(after: "--output", in: arguments) else {
            throw CaptureError.usage("--output is required.\n\(usage)")
        }
        let scale = value(after: "--scale", in: arguments).flatMap(Double.init) ?? 2
        let windows = try await shareableWindows()
        guard let window = windows.first(where: { $0.windowID == windowId }) else {
            throw CaptureError.windowNotFound(windowId)
        }
        guard window.isOnScreen else {
            throw CaptureError.windowNotOnScreen(windowId)
        }
        let cropValues = (
            value(after: "--crop-x", in: arguments).flatMap(Double.init),
            value(after: "--crop-y", in: arguments).flatMap(Double.init),
            value(after: "--crop-width", in: arguments).flatMap(Double.init),
            value(after: "--crop-height", in: arguments).flatMap(Double.init)
        )
        let suppliedCropCount = [
            cropValues.0,
            cropValues.1,
            cropValues.2,
            cropValues.3,
        ].compactMap { $0 }.count
        guard suppliedCropCount == 0 || suppliedCropCount == 4 else {
            throw CaptureError.invalidCrop(
                "all four --crop-x/--crop-y/--crop-width/--crop-height values are required"
            )
        }
        let sourceRect: CGRect
        if let x = cropValues.0,
           let y = cropValues.1,
           let width = cropValues.2,
           let height = cropValues.3 {
            sourceRect = CGRect(x: x, y: y, width: width, height: height)
        } else {
            sourceRect = CGRect(
                x: 0,
                y: 0,
                width: window.frame.width,
                height: window.frame.height
            )
        }
        guard sourceRect.minX >= 0,
              sourceRect.minY >= 0,
              sourceRect.width > 0,
              sourceRect.height > 0,
              sourceRect.maxX <= window.frame.width,
              sourceRect.maxY <= window.frame.height else {
            throw CaptureError.invalidCrop(
                "\(sourceRect) is outside \(window.frame.width)x\(window.frame.height)"
            )
        }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int(sourceRect.width * scale))
        configuration.height = max(1, Int(sourceRect.height * scale))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let startedAt = Date()
        let monotonicStart = DispatchTime.now().uptimeNanoseconds
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let monotonicEnd = DispatchTime.now().uptimeNanoseconds
        let completedAt = Date()
        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            throw CaptureError.pngEncodingFailed
        }
        let output = URL(fileURLWithPath: outputValue)
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try png.write(to: output, options: .atomic)
        try emit(
            CaptureResult(
                output: output.path,
                pixelWidth: image.width,
                pixelHeight: image.height,
                sourceRect: RectRecord(
                    x: sourceRect.origin.x,
                    y: sourceRect.origin.y,
                    width: sourceRect.width,
                    height: sourceRect.height
                ),
                window: record(for: window),
                captureTiming: CaptureTimingRecord(
                    startedAt: iso8601(startedAt),
                    completedAt: iso8601(completedAt),
                    monotonicStartNanoseconds: String(monotonicStart),
                    monotonicEndNanoseconds: String(monotonicEnd),
                    durationMilliseconds: Double(monotonicEnd - monotonicStart) / 1_000_000
                )
            )
        )
    }

    private static func motion(arguments: [String]) async throws {
        guard let rawWindowId = value(after: "--window-id", in: arguments),
              let windowId = UInt32(rawWindowId) else {
            throw CaptureError.usage("--window-id is required.\n\(usage)")
        }
        guard let outputValue = value(after: "--output", in: arguments),
              !outputValue.isEmpty else {
            throw CaptureError.usage("--output DIRECTORY is required.\n\(usage)")
        }
        guard let duration = value(after: "--duration-seconds", in: arguments)
            .flatMap(Double.init),
              duration.isFinite,
              duration > 0,
              duration <= 300 else {
            throw CaptureError.invalidMotion(
                "--duration-seconds must be finite, greater than zero, and at most 300"
            )
        }
        guard let eventBinding = value(after: "--event-frame-zero", in: arguments),
              !eventBinding.isEmpty else {
            throw CaptureError.invalidMotion("--event-frame-zero is required")
        }
        guard let expectedPID = value(after: "--expected-pid", in: arguments)
            .flatMap(Int32.init) else {
            throw CaptureError.authenticity("--expected-pid is required")
        }
        guard let expectedBundleID = value(after: "--expected-bundle-id", in: arguments),
              !expectedBundleID.isEmpty else {
            throw CaptureError.authenticity("--expected-bundle-id is required")
        }
        let scale = value(after: "--scale", in: arguments).flatMap(Double.init) ?? 2
        guard scale.isFinite, scale > 0 else {
            throw CaptureError.invalidMotion("--scale must be finite and positive")
        }
        let windows = try await shareableWindows()
        guard let window = windows.first(where: { $0.windowID == windowId }) else {
            throw CaptureError.windowNotFound(windowId)
        }
        try validateAuthenticity(
            window: window,
            expectedPID: expectedPID,
            expectedBundleID: expectedBundleID
        )
        let sourceRect = try resolvedSourceRect(arguments: arguments, window: window)
        let pixelWidth = max(1, Int(sourceRect.width * scale))
        let pixelHeight = max(1, Int(sourceRect.height * scale))
        let outputDirectory = URL(fileURLWithPath: outputValue, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
            throw CaptureError.invalidMotion(
                "output directory already exists; refusing to overwrite \(outputDirectory.path)"
            )
        }
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = pixelWidth
        configuration.height = pixelHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let collector = MotionCollector(
            outputDirectory: outputDirectory,
            expectedWidth: pixelWidth,
            expectedHeight: pixelHeight
        )
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: collector
        )
        let callbackQueue = DispatchQueue(
            label: "com.open-vibe-island.halo-window-capture.motion"
        )
        try stream.addStreamOutput(
            collector,
            type: .screen,
            sampleHandlerQueue: callbackQueue
        )
        let startedAt = Date()
        let monotonicStart = DispatchTime.now().uptimeNanoseconds
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(duration))
        callbackQueue.sync {}
        let collected = try collector.seal()
        try await stream.stopCapture()
        let monotonicEnd = DispatchTime.now().uptimeNanoseconds
        let completedAt = Date()

        let refreshedWindows = try await shareableWindows()
        guard let refreshed = refreshedWindows.first(where: { $0.windowID == windowId }) else {
            throw CaptureError.authenticity(
                "window \(windowId) disappeared before capture provenance closed"
            )
        }
        try validateAuthenticity(
            window: refreshed,
            expectedPID: expectedPID,
            expectedBundleID: expectedBundleID
        )
        let originalRecord = record(for: window)
        let refreshedRecord = record(for: refreshed)
        guard originalRecord.cgWindowId == refreshedRecord.cgWindowId,
              originalRecord.ownerPid == refreshedRecord.ownerPid,
              originalRecord.ownerBundleId == refreshedRecord.ownerBundleId,
              originalRecord.bounds == refreshedRecord.bounds else {
            throw CaptureError.authenticity(
                "window identity or bounds changed during capture"
            )
        }
        let frames = collected.frames
        guard let first = frames.first, let last = frames.last else {
            throw CaptureError.invalidMotion("no frames were delivered")
        }
        let displayPair = try await MainActor.run {
            (
                try displayRecord(for: window),
                try displayRecord(for: refreshed)
            )
        }
        guard displayPair.0 == displayPair.1 else {
            throw CaptureError.authenticity(
                "window resolved to a different display during capture"
            )
        }
        let display = displayPair.0
        let intervals = frames.compactMap(\.observedIntervalSeconds)
        let jitter = jitterRecord(intervals: intervals)
        let duplicateCount = frames.filter(\.duplicate).count
        let inferredDroppedCount = collected.drops
            .filter { $0.signal == "pts-gap" }
            .reduce(0) { $0 + $1.count }
        let nonCompleteAttachmentCount = collected.drops
            .filter { $0.signal == "screen-capture-kit-attachment" }
            .reduce(0) { $0 + $1.count }
        let droppedCount = max(inferredDroppedCount, nonCompleteAttachmentCount)
        let manifestURL = outputDirectory.appendingPathComponent("motion.json")
        let result = MotionResult(
            outputDirectory: outputDirectory.path,
            manifest: manifestURL.path,
            nominalFramesPerSecond: 60,
            requestedDurationSeconds: duration,
            actualPTSRangeSeconds: last.ptsSeconds - first.ptsSeconds,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            sourceRect: rectRecord(sourceRect),
            scale: scale,
            window: originalRecord,
            display: display,
            expectedOwnerPid: expectedPID,
            expectedOwnerBundleId: expectedBundleID,
            captureTiming: CaptureTimingRecord(
                startedAt: iso8601(startedAt),
                completedAt: iso8601(completedAt),
                monotonicStartNanoseconds: String(monotonicStart),
                monotonicEndNanoseconds: String(monotonicEnd),
                durationMilliseconds: Double(monotonicEnd - monotonicStart) / 1_000_000
            ),
            eventFrameZero: EventFrameZeroRecord(
                callerBinding: eventBinding,
                frameIndex: 0,
                ptsSeconds: first.ptsSeconds,
                callbackMonotonicNanoseconds: first.callbackMonotonicNanoseconds,
                basis: "caller binding attached to first delivered complete frame after stream start"
            ),
            frames: frames,
            droppedFrames: collected.drops,
            duplicateFrameCount: duplicateCount,
            droppedFrameCount: droppedCount,
            inferredDroppedFrameCount: inferredDroppedCount,
            nonCompleteAttachmentCount: nonCompleteAttachmentCount,
            jitter: jitter
        )
        try writeJSON(result, to: manifestURL)
        try emit(result)
    }

    private static func record(for window: SCWindow) -> WindowRecord {
        let owner = window.owningApplication
        return WindowRecord(
            cgWindowId: window.windowID,
            ownerPid: owner?.processID,
            ownerBundleId: owner?.bundleIdentifier,
            ownerName: owner?.applicationName,
            title: window.title,
            bounds: RectRecord(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: window.frame.width,
                height: window.frame.height
            ),
            layer: window.windowLayer,
            isOnScreen: window.isOnScreen
        )
    }

    private static func resolvedSourceRect(
        arguments: [String],
        window: SCWindow
    ) throws -> CGRect {
        let values = (
            value(after: "--crop-x", in: arguments).flatMap(Double.init),
            value(after: "--crop-y", in: arguments).flatMap(Double.init),
            value(after: "--crop-width", in: arguments).flatMap(Double.init),
            value(after: "--crop-height", in: arguments).flatMap(Double.init)
        )
        let supplied = [values.0, values.1, values.2, values.3].compactMap { $0 }.count
        guard supplied == 0 || supplied == 4 else {
            throw CaptureError.invalidCrop(
                "all four --crop-x/--crop-y/--crop-width/--crop-height values are required"
            )
        }
        let rect: CGRect
        if let x = values.0,
           let y = values.1,
           let width = values.2,
           let height = values.3 {
            rect = CGRect(x: x, y: y, width: width, height: height)
        } else {
            rect = CGRect(origin: .zero, size: window.frame.size)
        }
        guard rect.minX.isFinite,
              rect.minY.isFinite,
              rect.width.isFinite,
              rect.height.isFinite,
              rect.minX >= 0,
              rect.minY >= 0,
              rect.width > 0,
              rect.height > 0,
              rect.maxX <= window.frame.width,
              rect.maxY <= window.frame.height else {
            throw CaptureError.invalidCrop(
                "\(rect) is outside \(window.frame.width)x\(window.frame.height)"
            )
        }
        return rect
    }

    private static func validateAuthenticity(
        window: SCWindow,
        expectedPID: Int32,
        expectedBundleID: String
    ) throws {
        guard window.isOnScreen else {
            throw CaptureError.windowNotOnScreen(window.windowID)
        }
        guard window.owningApplication?.processID == expectedPID else {
            throw CaptureError.authenticity(
                "expected PID \(expectedPID), got \(window.owningApplication?.processID.description ?? "nil")"
            )
        }
        guard window.owningApplication?.bundleIdentifier == expectedBundleID else {
            throw CaptureError.authenticity(
                "expected bundle \(expectedBundleID), got \(window.owningApplication?.bundleIdentifier ?? "nil")"
            )
        }
    }

    @MainActor
    private static func displayRecord(for window: SCWindow) throws -> DisplayRecord {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            throw CaptureError.authenticity("unable to enumerate active displays")
        }
        var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(displayCount))
        guard CGGetActiveDisplayList(
            displayCount,
            &displayIDs,
            &displayCount
        ) == .success else {
            throw CaptureError.authenticity("unable to read active display identities")
        }
        let matches = displayIDs.prefix(Int(displayCount)).compactMap {
            displayID -> (CGDirectDisplayID, CGRect, CGFloat)? in
            let displayBounds = CGDisplayBounds(displayID)
            let overlap = displayBounds.intersection(window.frame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else {
                return nil
            }
            return (displayID, displayBounds, overlap.width * overlap.height)
        }
        guard let match = matches.max(by: { $0.2 < $1.2 }),
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[
                      NSDeviceDescriptionKey("NSScreenNumber")
                  ] as? NSNumber)?.uint32Value == match.0
              }),
              let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber else {
            throw CaptureError.authenticity(
                "captured window does not resolve to an active display"
            )
        }
        let displayID = number.uint32Value
        let displayMode = CGDisplayCopyDisplayMode(displayID)
        return DisplayRecord(
            displayId: displayID,
            localizedName: screen.localizedName,
            framePoints: rectRecord(match.1),
            backingScale: screen.backingScaleFactor,
            pixelWidth: displayMode?.pixelWidth ?? Int(CGDisplayPixelsWide(displayID)),
            pixelHeight: displayMode?.pixelHeight ?? Int(CGDisplayPixelsHigh(displayID))
        )
    }

    private static func jitterRecord(intervals: [Double]) -> JitterRecord {
        let expected = 1.0 / 60.0
        guard !intervals.isEmpty else {
            return JitterRecord(
                sampleCount: 0,
                expectedIntervalSeconds: expected,
                meanObservedIntervalSeconds: nil,
                minimumObservedIntervalSeconds: nil,
                maximumObservedIntervalSeconds: nil,
                standardDeviationSeconds: nil,
                p95AbsoluteErrorSeconds: nil,
                effectiveFramesPerSecond: nil
            )
        }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(intervals.count)
        let errors = intervals.map { abs($0 - expected) }.sorted()
        let p95Index = min(
            errors.count - 1,
            max(0, Int(ceil(Double(errors.count) * 0.95)) - 1)
        )
        return JitterRecord(
            sampleCount: intervals.count,
            expectedIntervalSeconds: expected,
            meanObservedIntervalSeconds: mean,
            minimumObservedIntervalSeconds: intervals.min(),
            maximumObservedIntervalSeconds: intervals.max(),
            standardDeviationSeconds: sqrt(variance),
            p95AbsoluteErrorSeconds: errors[p95Index],
            effectiveFramesPerSecond: mean > 0 ? 1 / mean : nil
        )
    }

    private static func rectRecord(_ rect: CGRect) -> RectRecord {
        RectRecord(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func emit<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private static func emit(_ value: [String: Bool]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
