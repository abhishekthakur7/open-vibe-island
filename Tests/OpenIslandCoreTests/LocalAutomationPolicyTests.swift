import Foundation
import Testing
@testable import OpenIslandCore

struct LocalAutomationPolicyTests {
    @Test(arguments: [
        "curl", "ssh", "brew", "open", "/bin/sh", "cmux\nfocus", "--help", "com.apple.Terminal;open", "file:///tmp",
    ])
    func rejectsUnapprovedBundleAndActionInput(_ value: String) {
        #expect(throws: LocalAutomationPolicyError.invalidBundleIdentifier) {
            try LocalAutomationPolicy.validateTerminalBundleIdentifier(value)
        }
    }

    @Test func rejectsRoleMismatch() {
        #expect(throws: LocalAutomationPolicyError.unauthorizedRole) {
            try LocalAutomationPolicy.authorize(.inspectProcessSnapshot, role: .hookEventSubmit)
        }
    }

    @Test(arguments: ["https://example.invalid", "ssh://host", "mailto:a@b.invalid", "codex://threads/a"])
    func rejectsRemoteAndCustomURLs(_ value: String) {
        #expect(throws: LocalAutomationPolicyError.invalidURL) {
            try LocalAutomationPolicy.validateURL(URL(string: value)!)
        }
    }

    @Test func appleScriptTemplateIsFixedAndDataCannotBecomeSource() throws {
        for bad in ["x\"\n do shell script \"curl example.invalid\"", "--help", "a;b", "a b", "$(open /tmp)"] {
            #expect(throws: LocalAutomationPolicyError.invalidArgument) {
                try LocalProcessRunner.shared.runAppleScript(.ghosttyFocus, parameters: [bad])
            }
        }
    }

    @Test func everyAutomationActionRejectsNonAppRole() {
        for action in LocalAutomationAction.allCases {
            #expect(throws: LocalAutomationPolicyError.unauthorizedRole) {
                try LocalAutomationPolicy.authorize(action, role: .hookEventSubmit)
            }
        }
    }

    @Test func localFileValidationRejectsTraversalOptionsMetacharactersAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("open-island-policy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let regular = root.appendingPathComponent("safe.json")
        try Data("{}".utf8).write(to: regular)
        let symlink = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: regular)

        #expect(try LocalAutomationPolicy.validatedLocalFileURL(regular, beneath: root) == regular)
        for path in [
            root.appendingPathComponent("../safe.json"),
            root.appendingPathComponent("-option"),
            root.appendingPathComponent("bad;open"),
            root.appendingPathComponent("line\nbreak"),
            symlink,
        ] {
            #expect(throws: LocalAutomationPolicyError.invalidLocalPath) {
                try LocalAutomationPolicy.validatedLocalFileURL(path, beneath: root)
            }
        }
    }
}
