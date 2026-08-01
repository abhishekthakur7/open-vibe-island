import Foundation
import Testing
@testable import OpenIslandCore

struct KimiHooksTests {
    @Test
    func installIntoEmptyConfigEmitsAllManagedBlocks() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: nil,
            hookCommand: command
        )

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)
        let contents = try! #require(mutation.contents)

        for event in ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "PreToolUse", "PostToolUse"] {
            #expect(contents.contains("event = \"\(event)\""))
        }

        #expect(contents.contains(KimiHookInstaller.markerComment))
        #expect(contents.contains("--source kimi"))
        #expect(contents.contains("timeout = \(KimiHookInstaller.managedTimeout)"))
    }

    @Test
    func installPreservesUnrelatedUserHooks() {
        let userToml = """
        default_model = "kimi-for-coding"

        [[hooks]]
        event = "PostToolUse"
        matcher = "WriteFile"
        command = "prettier --write"

        """
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let mutation = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let contents = try! #require(mutation.contents)
        #expect(contents.contains("prettier --write"))
        #expect(contents.contains("default_model = \"kimi-for-coding\""))
        #expect(contents.contains(KimiHookInstaller.markerComment))
    }

    @Test
    func reinstallIsIdempotent() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let firstInstall = KimiHookInstaller.installConfigTOML(
            existingContents: nil,
            hookCommand: command
        )
        let secondInstall = KimiHookInstaller.installConfigTOML(
            existingContents: firstInstall.contents,
            hookCommand: command
        )

        #expect(secondInstall.contents == firstInstall.contents)
        #expect(secondInstall.changed == false)
    }

    @Test
    func uninstallRemovesManagedBlocksAndKeepsUserHooks() {
        let command = KimiHookInstaller.hookCommand(for: "/opt/open-island/OpenIslandHooks")
        let userToml = """
        default_model = "kimi-for-coding"

        [[hooks]]
        event = "PostToolUse"
        matcher = "WriteFile"
        command = "prettier --write"

        """
        let installed = KimiHookInstaller.installConfigTOML(
            existingContents: userToml,
            hookCommand: command
        )

        let uninstall = KimiHookInstaller.uninstallConfigTOML(
            existingContents: installed.contents,
            managedCommand: command
        )

        #expect(uninstall.changed)
        let remaining = try! #require(uninstall.contents)
        #expect(remaining.contains("prettier --write"))
        #expect(remaining.contains("default_model"))
        #expect(remaining.contains(KimiHookInstaller.markerComment) == false)
        #expect(remaining.contains("--source kimi") == false)
    }

    @Test
    func resolvedAgentToolMapsKimiSource() {
        var payload = ClaudeHookPayload(
            cwd: "/tmp",
            hookEventName: .sessionStart,
            sessionID: "kimi-session-1"
        )
        payload.hookSource = "kimi"

        #expect(payload.resolvedAgentTool == .kimiCLI)
    }
}
