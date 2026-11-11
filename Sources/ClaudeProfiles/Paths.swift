import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let appSupport = home.appendingPathComponent("Library/Application Support")
    static let root = appSupport.appendingPathComponent("Claude-Profiles")
    static let registry = root.appendingPathComponent("profiles.json")
    static let backups = appSupport.appendingPathComponent("Claude-Profiles Backups")
    static let defaultData = appSupport.appendingPathComponent("Claude")
    static let profileApps = home.appendingPathComponent("Applications/Claude Profiles")
    static let menuBarApp = home.appendingPathComponent("Applications/Claude Profiles.app")
    static let installedBinary = home.appendingPathComponent(".local/bin/claude-profiles")
    static let installedLauncher = root.appendingPathComponent("claude-profile-launcher")
    static let agentLabel = "local.claude-profiles.menubar"
    static let launchAgent = home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    static let claudeApp = URL(fileURLWithPath: "/Applications/Claude.app")
    static let claudeBundleID = "com.anthropic.claudefordesktop"
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static var currentExecutable: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    static var isSourceBuild: Bool {
        currentExecutable.path.contains("/.build/")
    }

    static var launcher: URL? {
        let directory = currentExecutable.deletingLastPathComponent()
        let candidates = [
            directory.appendingPathComponent("claude-profile-launcher"),
            directory.deletingLastPathComponent().appendingPathComponent("libexec/claude-profile-launcher"),
            installedLauncher,
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
