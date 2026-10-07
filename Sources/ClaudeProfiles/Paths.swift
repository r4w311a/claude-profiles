import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let appSupport = home.appendingPathComponent("Library/Application Support")
    static let root = appSupport.appendingPathComponent("Claude-Profiles")
    static let registry = root.appendingPathComponent("profiles.json")
    static let defaultData = appSupport.appendingPathComponent("Claude")
    static let launchers = home.appendingPathComponent("Applications/Claude Profiles")
    static let menuBarApp = home.appendingPathComponent("Applications/Claude Profiles.app")
    static let installedBinary = home.appendingPathComponent(".local/bin/claude-profiles")
    static let launchAgent = home.appendingPathComponent("Library/LaunchAgents/\(Bundles.agentLabel).plist")
    static let claudeApp = URL(fileURLWithPath: "/Applications/Claude.app")
    static let claudeBundleID = "com.anthropic.claudefordesktop"
}
