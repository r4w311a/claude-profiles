import AppKit
import Foundation

enum Installer {
    static let menuBarKey = "ClaudeProfilesMenuBar"
    static let menuBarBundleID = "local.claude-profiles"

    static var isLoginItemInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.launchAgent.path)
    }

    static func install() throws {
        guard let launcher = Paths.launcher else {
            throw ProfileError("claude-profile-launcher was not built. Run ./install.sh.")
        }
        let menuBarApps = NSRunningApplication.runningApplications(withBundleIdentifier: menuBarBundleID)
        menuBarApps.forEach { $0.terminate() }

        if Paths.isSourceBuild {
            try copyExecutable(Paths.currentExecutable, to: Paths.installedBinary)
            print("Installed \(Paths.installedBinary.path)")
        }
        try copyExecutable(launcher, to: Paths.installedLauncher)

        try writeMenuBarApp(launcher: launcher)
        print("Menu bar app: \(Paths.menuBarApp.path)")
        if isLoginItemInstalled { try installLoginItem() }

        let registry = Registry.load()
        ProfileApps.removeLegacyLaunchers(keeping: registry)
        let outcome = Updater.update(registry.profiles, restartRunning: false) { print("Building \($0.appName)…") }
        Commands.report(outcome)

        if NSRunningApplication.runningApplications(withBundleIdentifier: Paths.claudeBundleID).count > 1 {
            print("A profile from the old setup is still running inside the original Claude app.")
            print("Quit that window with Cmd+Q, then open the profile's own app, for example \"Claude Work\".")
        }
        Shell.run("/usr/bin/open", [Paths.menuBarApp.path])
    }

    static func uninstall(removeData: Bool, backUpFirst: Bool) throws {
        let profiles = Registry.load().profiles.filter { !$0.isDefault }
        let running = profiles.filter { $0.running != nil }
        guard running.isEmpty else {
            throw ProfileError("Quit \(running.map(\.appName).joined(separator: ", ")) first.")
        }
        if removeData, backUpFirst {
            for profile in profiles where FileManager.default.fileExists(atPath: profile.resolvedDataDir) {
                print("Backing up \(profile.name)…")
                print("Saved \(try Backups.create(for: profile).path)")
            }
        }
        uninstallLoginItem()
        NSRunningApplication.runningApplications(withBundleIdentifier: menuBarBundleID).forEach { $0.terminate() }
        let fileManager = FileManager.default
        for item in [Paths.menuBarApp, Paths.profileApps] where fileManager.fileExists(atPath: item.path) {
            try fileManager.trashItem(at: item, resultingItemURL: nil)
            print("Moved \(item.path) to the Trash.")
        }
        try? fileManager.removeItem(at: Paths.installedLauncher)

        if removeData {
            for profile in profiles { Shell.run("/usr/bin/tccutil", ["reset", "All", profile.bundleID]) }
            removeUserData()
        } else {
            print("Your profile logins and chats are still in \(Paths.root.path).")
            print("Run `claude-profiles uninstall --all` to remove them too.")
        }

        if Paths.currentExecutable.path.contains("/Cellar/") {
            print("Run `brew uninstall claude-profiles` to remove the command.")
        } else if fileManager.fileExists(atPath: Paths.installedBinary.path) {
            try? fileManager.removeItem(at: Paths.installedBinary)
            print("Removed \(Paths.installedBinary.path).")
        }
    }

    private static func removeUserData() {
        let fileManager = FileManager.default
        let library = Paths.home.appendingPathComponent("Library")
        var items = [Paths.root]
        for folder in ["Preferences", "Caches", "HTTPStorages", "Saved Application State"] {
            let directory = library.appendingPathComponent(folder)
            let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            items += names.filter { $0.hasPrefix(menuBarBundleID) }.map { directory.appendingPathComponent($0) }
        }
        for item in items where fileManager.fileExists(atPath: item.path) {
            if item.pathExtension == "plist" {
                Shell.run("/usr/bin/defaults", ["delete", item.deletingPathExtension().lastPathComponent])
            }
            guard (try? fileManager.trashItem(at: item, resultingItemURL: nil)) != nil else { continue }
            print("Moved \(item.path) to the Trash.")
        }
    }

    static func installLoginItem() throws {
        let plist: [String: Any] = [
            "Label": Paths.agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Paths.menuBarApp.path, "--args", MenuBarApp.backgroundFlag],
            "RunAtLoad": true,
        ]
        try FileManager.default.createDirectory(at: Paths.launchAgent.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: Paths.launchAgent)
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Paths.agentLabel)"])
        let result = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", Paths.launchAgent.path])
        guard result.succeeded else { throw ProfileError("launchctl could not load the login item: \(result.error)") }
    }

    static func uninstallLoginItem() {
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Paths.agentLabel)"])
        try? FileManager.default.removeItem(at: Paths.launchAgent)
    }

    private static func copyExecutable(_ source: URL, to destination: URL) throws {
        guard source.standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else { return }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func writeMenuBarApp(launcher: URL) throws {
        let fileManager = FileManager.default
        let bundle = Paths.menuBarApp
        let contents = bundle.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        if fileManager.fileExists(atPath: bundle.path) { try fileManager.removeItem(at: bundle) }
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        try fileManager.copyItem(at: Paths.currentExecutable, to: macOS.appendingPathComponent("claude-profiles"))
        try fileManager.copyItem(at: launcher, to: macOS.appendingPathComponent("claude-profile-launcher"))
        try ProfileIcon.writeManagerIcon(to: resources.appendingPathComponent("AppIcon.icns"))

        let info: [String: Any] = [
            "CFBundleExecutable": "claude-profiles",
            "CFBundleIdentifier": menuBarBundleID,
            "CFBundleName": "Claude Profiles",
            "CFBundleDisplayName": "Claude Profiles",
            "CFBundleIconFile": "AppIcon",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": Version.current,
            "CFBundleVersion": Version.current,
            "LSMinimumSystemVersion": "13.0",
            "LSUIElement": true,
            menuBarKey: true,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        Shell.run(Signing.codesign, ["--force", "--sign", "-", bundle.path])
        Shell.run(Paths.lsregister, ["-f", bundle.path])
    }
}
