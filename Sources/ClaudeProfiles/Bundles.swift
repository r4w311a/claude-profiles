import Foundation

/// Writes the small .app bundles that wrap this binary: one launcher per profile, plus the menu bar app.
/// Each bundle carries its own copy of the binary and tells it what to do through an Info.plist key.
enum Bundles {
    static let profileKey = "ClaudeProfileSlug"
    static let menuBarKey = "ClaudeProfilesMenuBar"
    static let agentLabel = "local.claude-profiles.menubar"

    static var currentExecutable: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    static func launcherURL(for profile: Profile) -> URL {
        Paths.launchers.appendingPathComponent("Claude \(profile.name).app")
    }

    @discardableResult
    static func writeLauncher(for profile: Profile) throws -> URL {
        let url = launcherURL(for: profile)
        try write(bundle: url, name: "Claude \(profile.name)", identifier: "local.claude-profiles.\(profile.slug)",
                  extra: [profileKey: profile.slug])
        return url
    }

    static func writeMenuBarApp() throws {
        try write(bundle: Paths.menuBarApp, name: "Claude Profiles", identifier: "local.claude-profiles",
                  extra: [menuBarKey: true])
    }

    static func removeLauncher(for profile: Profile) {
        let url = launcherURL(for: profile)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private static func write(bundle: URL, name: String, identifier: String, extra: [String: Any]) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: bundle.path) { try fm.removeItem(at: bundle) }
        let contents = bundle.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        try fm.copyItem(at: currentExecutable, to: macOS.appendingPathComponent("claude-profiles"))
        let icon = Paths.claudeApp.appendingPathComponent("Contents/Resources/electron.icns")
        if fm.fileExists(atPath: icon.path) {
            try fm.copyItem(at: icon, to: resources.appendingPathComponent("AppIcon.icns"))
        }

        var plist: [String: Any] = [
            "CFBundleExecutable": "claude-profiles",
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
        ]
        plist.merge(extra) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        _ = run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
        // Nudge Launch Services so Spotlight and Launchpad pick up the new bundle right away.
        _ = run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                ["-f", bundle.path])
    }

    // MARK: - Login item

    static func installAgent() throws {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Paths.menuBarApp.path],
            "RunAtLoad": true,
        ]
        try FileManager.default.createDirectory(at: Paths.launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: Paths.launchAgent)
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
        guard run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", Paths.launchAgent.path]) == 0 else {
            throw ProfileError("launchctl couldn't load \(Paths.launchAgent.path).")
        }
    }

    static func uninstallAgent() {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
        try? FileManager.default.removeItem(at: Paths.launchAgent)
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
