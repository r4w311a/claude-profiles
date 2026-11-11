import AppKit
import Darwin
import Foundation

enum ProfileApps {
    enum State: String {
        case current, outdated, missing
    }

    static let slugKey = "ClaudeProfileSlug"
    static let dataDirKey = "ClaudeProfileDataDir"
    static let colorKey = "ClaudeProfileColor"
    static let formatKey = "ClaudeProfileFormat"
    static let formatVersion = 2
    static let launcherName = "Claude Profile"
    static let iconName = "ProfileIcon"
    static let removedInfoKeys = [
        "CFBundleURLTypes", "CFBundleDocumentTypes", "UTExportedTypeDeclarations",
        "UTImportedTypeDeclarations", "NSUserActivityTypes", "CFBundleIconName",
    ]

    static var claudeVersion: String? {
        info(at: Paths.claudeApp)?["CFBundleVersion"] as? String
    }

    static func info(at app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    static func state(of profile: Profile) -> State {
        guard !profile.isDefault else { return .current }
        guard let info = info(at: profile.appURL) else { return .missing }
        let matches = info[slugKey] as? String == profile.slug
            && info[dataDirKey] as? String == profile.dataDir
            && info[colorKey] as? String == profile.color
            && info[formatKey] as? Int == formatVersion
            && info["CFBundleDisplayName"] as? String == profile.appName
            && info["CFBundleVersion"] as? String == claudeVersion
        return matches ? .current : .outdated
    }

    static func needsBuild(_ profile: Profile) -> Bool {
        state(of: profile) != .current
    }

    static func build(_ profile: Profile) throws {
        guard let dataDir = profile.dataDir else { return }
        guard profile.runningApp == nil else { throw ProfileError("Quit \(profile.appName) before rebuilding it.") }
        guard FileManager.default.fileExists(atPath: Paths.claudeApp.path) else {
            throw ProfileError("Claude Desktop was not found at \(Paths.claudeApp.path).")
        }
        guard let launcher = Paths.launcher else {
            throw ProfileError("The profile launcher is missing. Run ./install.sh again.")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: Paths.profileApps, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: dataDir, withIntermediateDirectories: true)

        let staging = Paths.profileApps.appendingPathComponent(".\(profile.slug).building.app")
        try? fileManager.removeItem(at: staging)
        do {
            try clone(Paths.claudeApp, to: staging)
            try writeInfo(for: profile, dataDir: dataDir, in: staging)
            try ProfileIcon.write(for: profile, to: staging.appendingPathComponent("Contents/Resources/\(iconName).icns"))
            try fileManager.copyItem(at: launcher, to: staging.appendingPathComponent("Contents/MacOS/\(launcherName)"))
            try Signing.sign(staging.appendingPathComponent("Contents/MacOS/Claude"),
                             entitlements: Signing.profileEntitlements(from: Paths.claudeApp))
            try Signing.sign(staging)
            try replace(profile.appURL, with: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        Shell.run(Paths.lsregister, ["-f", profile.appURL.path])
    }

    static func remove(_ profile: Profile) throws {
        guard !profile.isDefault, FileManager.default.fileExists(atPath: profile.appURL.path) else { return }
        try FileManager.default.trashItem(at: profile.appURL, resultingItemURL: nil)
    }

    static func removeLegacyLaunchers(keeping registry: Registry) {
        let profileApps = Set(registry.profiles.filter { !$0.isDefault }.map(\.appURL.lastPathComponent))
        let contents = (try? FileManager.default.contentsOfDirectory(at: Paths.profileApps,
                                                                     includingPropertiesForKeys: nil)) ?? []
        for app in contents where app.pathExtension == "app" && !profileApps.contains(app.lastPathComponent) {
            guard let info = info(at: app), info[slugKey] != nil, info[dataDirKey] == nil else { continue }
            try? FileManager.default.trashItem(at: app, resultingItemURL: nil)
        }
    }

    static func open(_ profile: Profile, completion: @escaping (Error?) -> Void) {
        do {
            if profile.runningApp == nil, needsBuild(profile) { try build(profile) }
        } catch {
            completion(error)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: profile.appURL, configuration: configuration) { _, error in
            completion(error)
        }
    }

    @discardableResult
    static func quit(_ profile: Profile) -> pid_t? {
        guard let (app, pid) = profile.running else { return nil }
        if !app.terminate() { kill(pid, SIGTERM) }
        return pid
    }

    static func quitAndWait(_ profile: Profile, timeout: TimeInterval = 20) -> Bool {
        guard let pid = quit(profile) else { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while ProcessLookup.isAlive(pid), Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return !ProcessLookup.isAlive(pid)
    }

    private static func clone(_ source: URL, to destination: URL) throws {
        if clonefile(source.path, destination.path, 0) == 0 { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func writeInfo(for profile: Profile, dataDir: String, in app: URL) throws {
        let url = app.appendingPathComponent("Contents/Info.plist")
        guard var info = NSDictionary(contentsOf: url) as? [String: Any] else {
            throw ProfileError("Could not read Claude's Info.plist.")
        }
        for key in removedInfoKeys { info.removeValue(forKey: key) }
        info["CFBundleIdentifier"] = profile.bundleID
        info["CFBundleDisplayName"] = profile.appName
        info["CFBundleExecutable"] = launcherName
        info["CFBundleIconFile"] = iconName
        info[slugKey] = profile.slug
        info[dataDirKey] = dataDir
        info[colorKey] = profile.color
        info[formatKey] = formatVersion
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url)
    }

    private static func replace(_ destination: URL, with staging: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: staging, to: destination)
    }
}
