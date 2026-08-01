import Foundation
import Testing
@testable import OpenIslandCore

struct WorkspaceNameResolverTests {
    @Test
    func gitBranchReadsNormalRepositoryHead() throws {
        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }

        let git = repo.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        try "ref: refs/heads/feat/v8-engineering\n".write(
            to: git.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "feat/v8-engineering")
    }

    @Test
    func gitBranchCachesResultAcrossRepeatedLookups() throws {
        // Pins the SwiftUI layout-loop fix: repeated lookups for the
        // same cwd must hit the in-memory cache instead of re-walking
        // the directory tree. Demonstrated by mutating HEAD between
        // calls — without the cache the second call would surface the
        // new branch immediately. With it, the cached value persists
        // until the cache is dropped.
        WorkspaceNameResolver.resetGitBranchCacheForTests()
        defer { WorkspaceNameResolver.resetGitBranchCacheForTests() }

        let repo = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repo) }

        let git = repo.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        let headURL = git.appendingPathComponent("HEAD")
        try "ref: refs/heads/cached-branch\n".write(to: headURL, atomically: true, encoding: .utf8)

        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "cached-branch")

        // Mutate underlying HEAD; cache must mask the change.
        try "ref: refs/heads/changed-branch\n".write(to: headURL, atomically: true, encoding: .utf8)
        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "cached-branch")

        // After the cache is dropped the new branch is observed.
        WorkspaceNameResolver.resetGitBranchCacheForTests()
        #expect(WorkspaceNameResolver.gitBranch(for: repo.path) == "changed-branch")
    }

    // MARK: - PI-C-003: workspace identity never leaks a raw path

    @Test
    func workspaceNameKeepsTheFolderNameForNormalPaths() {
        #expect(WorkspaceNameResolver.workspaceName(for: "/Users/x/dev/proj") == "proj")
        #expect(WorkspaceNameResolver.workspaceName(for: "/Users/x/dev/proj/") == "proj")
        #expect(WorkspaceNameResolver.workspaceName(for: "/Users/x/dev/my.project") == "my.project")
    }

    @Test
    func workspaceNameSubstitutesFallbackForRootAndMissingPaths() {
        // Poured design law 6: the label is always a bare human folder name, so
        // a root cwd (whose `lastPathComponent` is literally "/") and a missing
        // cwd both resolve to the "Workspace" substitute instead of leaking.
        #expect(WorkspaceNameResolver.workspaceName(for: "/") == "Workspace")
        #expect(WorkspaceNameResolver.workspaceName(for: "") == "Workspace")
        #expect(WorkspaceNameResolver.workspaceName(for: "   ") == "Workspace")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceNameResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
