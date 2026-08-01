import XCTest
@testable import OpenIslandApp
import OpenIslandCore

final class TerminalJumpServiceTests: XCTestCase {
    private final class InvocationBox: @unchecked Sendable {
        var template: LocalAppleScriptTemplate?
        var parameters: [String] = []
        var activated: String?
    }

    func testFocusUsesFixedTemplateAndOpaqueArgument() throws {
        let invocation = InvocationBox()
        let service = TerminalJumpService(
            automationRunner: { receivedTemplate, receivedParameters in
                invocation.template = receivedTemplate
                invocation.parameters = receivedParameters
                return "matched"
            },
            activationRunner: { _ in XCTFail("focus should not activate") }
        )

        let result = try service.jump(to: JumpTarget(terminalApp: "Ghostty", workspaceName: "x", paneTitle: "ignored", workingDirectory: "/tmp", terminalSessionID: "A1B2-C3D4"))

        XCTAssertEqual(result, "Focused the matching Ghostty terminal.")
        XCTAssertEqual(invocation.template, .ghosttyFocus)
        XCTAssertEqual(invocation.parameters, ["A1B2-C3D4"])
    }

    func testRejectsCommandLikeTerminalAndDoesNotActivateIt() {
        let service = TerminalJumpService(activationRunner: { _ in XCTFail("must not activate") })
        XCTAssertThrowsError(try service.jump(to: JumpTarget(terminalApp: "Ghostty\n/bin/sh", workspaceName: "x", paneTitle: "")))
    }

    func testUnsafeSurfaceValueFallsBackToFixedActivation() throws {
        let invocation = InvocationBox()
        let service = TerminalJumpService(
            automationRunner: { _, _ in XCTFail("unsafe value must not reach AppleScript"); return "" },
            activationRunner: { invocation.activated = $0 }
        )
        XCTAssertEqual(try service.jump(to: JumpTarget(terminalApp: "Terminal", workspaceName: "x", paneTitle: "", terminalTTY: "/dev/ttys001\nrun")), "Activated Terminal.")
        XCTAssertEqual(invocation.activated, "com.apple.Terminal")
    }

    func testWarpDoesNotSendKeystrokesOrPaneCommands() throws {
        let invocation = InvocationBox()
        let service = TerminalJumpService(activationRunner: { invocation.activated = $0 })
        XCTAssertEqual(try service.jump(to: JumpTarget(terminalApp: "Warp", workspaceName: "x", paneTitle: "", warpPaneUUID: "arbitrary")), "Activated Warp. Precise pane selection is unavailable in local-only mode.")
        XCTAssertEqual(invocation.activated, "dev.warp.Warp-Stable")
    }

    func testMultiplexerAndUnsupportedTerminalMetadataCannotTriggerAutomation() {
        for terminal in ["cmux", "tmux", "zellij", "wezterm"] {
            XCTAssertThrowsError(
                try TerminalJumpService().jump(to: JumpTarget(
                    terminalApp: terminal,
                    workspaceName: "x",
                    paneTitle: "",
                    terminalSessionID: "123"
                ))
            )
        }
    }
}
