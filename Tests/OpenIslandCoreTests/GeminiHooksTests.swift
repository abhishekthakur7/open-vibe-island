import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct GeminiHooksTests {
    @Test
    func geminiHookPayloadDecodesNotification() throws {
        let json = """
        {
          "cwd": "/tmp/worktree",
          "hook_event_name": "Notification",
          "session_id": "gemini-session-1",
          "message": "Gemini CLI requires permission to continue.",
          "notification_type": "ToolPermission",
          "details": {
            "tool_name": "run_shell_command",
            "file_path": "/tmp/worktree/package.json"
          }
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(GeminiHookPayload.self, from: json)

        #expect(payload.hookEventName == .notification)
        #expect(payload.notificationSummary == "Gemini CLI requires permission to continue.")
        #expect(payload.renderedDetails == "{file_path: /tmp/worktree/package.json, tool_name: run_shell_command}")
    }

    @Test
    func geminiHookInstallerInstallsIntoEmptySettingsFile() throws {
        let mutation = try GeminiHookInstaller.installSettingsJSON(
            existingData: nil,
            hookCommand: "/usr/local/bin/OpenIslandHooks --source gemini"
        )

        #expect(mutation.changed)
        #expect(mutation.managedHooksPresent)

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]

        #expect(hooks.keys.contains("SessionStart"))
        #expect(hooks.keys.contains("SessionEnd"))
        #expect(hooks.keys.contains("BeforeAgent"))
        #expect(hooks.keys.contains("AfterAgent"))
        #expect(hooks.keys.contains("Notification"))
    }

    @Test
    func geminiCompletionMessageUsesLastBodySegmentAndDropsRepeatedTail() {
        let response = """
        I'll review the integration guide and summarize the migration plan.

         

         
        The migration plan has three concrete steps:

        1. Update the request validation layer.
        2. Migrate the endpoint signatures to the new types.
        3. Regenerate the API examples for the docs.

        This keeps the rollout incremental and reduces migration risk for the API team.

        In short, the migration should stay incremental so each stage is easy to verify.

        he migration plan has three concrete steps:

        1. Update the request validation layer.
        2. Migrate the endpoint signatures to the new types.
        3. Regenerate the API examples for the docs.

        This keeps the rollout incremental and reduces migration risk for the API team.

        In short, the migration should stay incremental so each stage is easy to verify.
        """

        let session = AgentSession(
            id: "gemini-session-deduped",
            title: "Gemini CLI · repo",
            tool: .geminiCLI,
            phase: .completed,
            summary: "summary",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            geminiMetadata: GeminiSessionMetadata(
                lastAssistantMessage: "preview",
                lastAssistantMessageBody: response
            )
        )

        let completion = session.completionAssistantMessageText

        #expect(completion?.hasPrefix("The migration plan has three concrete steps:") == true)
        #expect(completion?.contains("I'll review the integration guide") == false)
        #expect(completion?.contains("\n\nhe migration plan has three concrete steps:") == false)
        #expect(completion?.components(separatedBy: "In short, the migration should stay incremental so each stage is easy to verify.").count == 2)
    }
}
