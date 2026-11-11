import Foundation

enum Backups {
    static let skippedFolders = [
        "Cache", "Code Cache", "GPUCache", "GPUPersistentCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "GraphiteDawnCache", "Crashpad", "sentry", "claude-code", "claude-code-vm",
    ]

    static let lossSummary = "Local Claude Code sessions, Cowork tasks, MCP servers, extensions, settings and the "
        + "saved login are deleted. Chats and Projects stay in the Claude account."

    static func create(for profile: Profile) throws -> URL {
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: profile.resolvedDataDir)
        guard fileManager.fileExists(atPath: source.path) else {
            throw ProfileError("\(profile.name) has no data to back up yet.")
        }
        try fileManager.createDirectory(at: Paths.backups, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let archive = Paths.backups.appendingPathComponent("\(profile.name) \(formatter.string(from: Date())).zip")
        let exclusions = (skippedFolders.map { "\($0)/*" } + ["Singleton*"]).flatMap { ["-x", $0] }
        let result = Shell.run("/usr/bin/zip", ["-r", "-q", "-y", archive.path, "."] + exclusions, in: source)
        guard result.succeeded else {
            try? fileManager.removeItem(at: archive)
            throw ProfileError("Backing up \(profile.name) failed: \(result.error)")
        }
        return archive
    }

    static func restore(_ profile: Profile, from archive: URL) throws {
        guard profile.running == nil else { throw ProfileError("Quit \(profile.appName) before restoring it.") }
        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: profile.resolvedDataDir)
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).restoring")
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        let result = Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        guard result.succeeded else {
            try? fileManager.removeItem(at: staging)
            throw ProfileError("Could not read \(archive.lastPathComponent): \(result.error)")
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.moveItem(at: staging, to: destination)
    }

    static func list(named name: String? = nil) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.backups, includingPropertiesForKeys: nil)) ?? []
        let prefix = name.map { "\($0) " } ?? ""
        return files
            .filter { $0.pathExtension == "zip" && $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func confirm(_ prompt: String, expecting answer: String) -> Bool {
        print("\(prompt) ", terminator: "")
        return readLine()?.trimmingCharacters(in: .whitespaces) == answer
    }
}
