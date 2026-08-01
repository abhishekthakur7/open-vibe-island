import Foundation
import Testing
@testable import OpenIslandCore

struct CursorHooksTests {
    @Test
    func cursorHookPayloadDecodesFromJSON() throws {
        let json = """
        {
            "hook_event_name": "beforeShellExecution",
            "conversation_id": "conv-123",
            "generation_id": "gen-456",
            "workspace_roots": ["/Users/test/project"],
            "command": "npm test",
            "cwd": "/Users/test/project"
        }
        """.data(using: .utf8)!

        let payload = try JSONDecoder().decode(CursorHookPayload.self, from: json)
        #expect(payload.hookEventName == .beforeShellExecution)
        #expect(payload.conversationId == "conv-123")
        #expect(payload.generationId == "gen-456")
        #expect(payload.workspaceRoots == ["/Users/test/project"])
        #expect(payload.command == "npm test")
        #expect(payload.cwd == "/Users/test/project")
        #expect(payload.sessionID == "conv-123")
        #expect(payload.isBlockingHook == true)
    }

    @Test
    func cursorHookDirectiveEncodesToJSON() throws {
        let directive = CursorHookDirective(continue: true, permission: .allow)
        let data = try JSONEncoder().encode(directive)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(object["continue"] as? Bool == true)
        #expect(object["permission"] as? String == "allow")
    }

    @Test
    func cursorHookInstallerInstallsIntoEmptyFile() throws {
        let mutation = try CursorHookInstaller.installHooksJSON(
            existingData: nil,
            hookCommand: "/usr/local/bin/OpenIslandHooks --source cursor"
        )

        #expect(mutation.changed == true)
        #expect(mutation.managedHooksPresent == true)

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]

        #expect(hooks.keys.contains("beforeShellExecution"))
        #expect(hooks.keys.contains("beforeMCPExecution"))
        #expect(hooks.keys.contains("stop"))

        let shellEntries = hooks["beforeShellExecution"] as! [[String: Any]]
        #expect(shellEntries.count == 1)
        #expect(shellEntries[0]["command"] as? String == "/usr/local/bin/OpenIslandHooks --source cursor")
    }

    @Test
    func cursorHookInstallerPreservesExistingHooks() throws {
        let existing = """
        {
            "version": 1,
            "hooks": {
                "beforeShellExecution": [
                    { "command": "/usr/local/bin/my-custom-hook" }
                ]
            }
        }
        """.data(using: .utf8)!

        let mutation = try CursorHookInstaller.installHooksJSON(
            existingData: existing,
            hookCommand: "/usr/local/bin/OpenIslandHooks --source cursor"
        )

        let data = try #require(mutation.contents)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = object["hooks"] as! [String: Any]
        let shellEntries = hooks["beforeShellExecution"] as! [[String: Any]]

        #expect(shellEntries.count == 2)
        #expect(shellEntries[0]["command"] as? String == "/usr/local/bin/my-custom-hook")
        #expect(shellEntries[1]["command"] as? String == "/usr/local/bin/OpenIslandHooks --source cursor")
    }

    @Test
    func cursorTranscriptReaderExtractsPromptWithUserQueryTag() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-transcript-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let entry = """
        {"role":"user","message":{"content":[{"type":"text","text":"<image_files>\\nSome image context\\n</image_files><user_query>\\n修复这个bug\\n</user_query>"}]}}
        """
        try entry.write(to: tempFile, atomically: true, encoding: .utf8)

        let prompt = CursorTranscriptReader.initialUserPrompt(at: tempFile.path)
        #expect(prompt == "修复这个bug")
    }

}
