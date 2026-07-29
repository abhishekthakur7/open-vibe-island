import Foundation
@testable import OpenIslandCore

func makeVerifiedHooksApp(at root: URL, contents: String = "bundled-helper") throws -> URL {
    let bundle = root.appendingPathComponent("Open Island.app", isDirectory: true)
    let helper = bundle.appendingPathComponent(VerifiedBundledHookArtifact.helperRelativePath)
    let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
    try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let data = Data(contents.utf8)
    try data.write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    let entry = BundledArtifactManifest.Entry(
        artifactID: VerifiedBundledHookArtifact.helperID,
        version: 1,
        relativePath: VerifiedBundledHookArtifact.helperRelativePath,
        sha256: ManagedHookFileSystem.digest(of: data),
        expectedMode: 0o755,
        managedMarker: "OpenIslandHooks",
        templateVersion: "1"
    )
    let manifest = BundledArtifactManifest(formatVersion: BundledArtifactManifest.formatVersion, artifacts: [entry])
    try JSONEncoder().encode(manifest).write(to: resources.appendingPathComponent(BundledArtifactManifest.fileName))
    return helper
}

func makeVerifiedOpenCodePluginApp(at root: URL) throws -> URL {
    let helper = try makeVerifiedHooksApp(at: root, contents: "opencode-helper")
    let bundle = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
    let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/OpenIslandApp/Resources/open-island-opencode.js")
    let pluginData = try Data(contentsOf: source)
    let plugin = resources.appendingPathComponent("open-island-opencode.js")
    try pluginData.write(to: plugin)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plugin.path)

    let manifestURL = resources.appendingPathComponent(BundledArtifactManifest.fileName)
    var manifest = try JSONDecoder().decode(BundledArtifactManifest.self, from: Data(contentsOf: manifestURL))
    manifest.artifacts.append(BundledArtifactManifest.Entry(
        artifactID: "resource:Contents/Resources/open-island-opencode.js",
        version: 1,
        relativePath: "Contents/Resources/open-island-opencode.js",
        sha256: ManagedHookFileSystem.digest(of: pluginData),
        expectedMode: 0o644,
        managedMarker: "static-resource",
        templateVersion: "1"
    ))
    try JSONEncoder().encode(manifest).write(to: manifestURL)
    return plugin
}

func makeVerifiedClaudeStatusLineTemplateResources(at root: URL) throws -> ClaudeStatusLineTemplateResources {
    let helper = try makeVerifiedHooksApp(at: root, contents: "status-line-helper")
    let bundle = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
    let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/OpenIslandApp/Resources/ClaudeStatusLineTemplates", isDirectory: true)
    let templates = resources.appendingPathComponent("ClaudeStatusLineTemplates", isDirectory: true)
    try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)

    let inventory: [(name: String, id: String)] = [
        ("status-line-v1.sh.template", "claude-statusline-script-template"),
        ("status-line-wrapper-v1.sh.template", "claude-statusline-wrapper-template"),
        ("status-line-delegate-v1.sh.template", "claude-statusline-delegate-template"),
    ]
    let manifestURL = resources.appendingPathComponent(BundledArtifactManifest.fileName)
    var manifest = try JSONDecoder().decode(BundledArtifactManifest.self, from: Data(contentsOf: manifestURL))
    for item in inventory {
        let source = sourceRoot.appendingPathComponent(item.name)
        let destination = templates.appendingPathComponent(item.name)
        let data = try Data(contentsOf: source)
        try data.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        manifest.artifacts.append(BundledArtifactManifest.Entry(
            artifactID: item.id,
            version: 1,
            relativePath: "Contents/Resources/ClaudeStatusLineTemplates/\(item.name)",
            sha256: ManagedHookFileSystem.digest(of: data),
            expectedMode: 0o644,
            managedMarker: ClaudeStatusLineInstallationManager.managedTemplateMarker,
            templateVersion: ClaudeStatusLineInstallationManager.managedTemplateVersion
        ))
    }
    try JSONEncoder().encode(manifest).write(to: manifestURL)
    return try ClaudeStatusLineTemplateResources(
        normal: VerifiedBundledHookArtifact.verifiedResource(at: templates.appendingPathComponent(inventory[0].name)),
        wrapper: VerifiedBundledHookArtifact.verifiedResource(at: templates.appendingPathComponent(inventory[1].name)),
        delegate: VerifiedBundledHookArtifact.verifiedResource(at: templates.appendingPathComponent(inventory[2].name))
    )
}
