import Foundation

enum Commands {
    static func list() {
        let registry = Registry.load()
        if registry.profiles.isEmpty {
            print("No profiles yet. Try `claude-profiles adopt-default Personal`.")
        }
        for profile in registry.profiles {
            let running = profile.runningApp.map { "running (pid \($0.processIdentifier))" } ?? "stopped"
            let state = profile.isDefault ? "original app" : ProfileApps.state(of: profile).rawValue
            print("\(pad(profile.name, 14)) \(pad(profile.color, 8)) \(pad(running, 22)) \(pad(state, 13)) \(profile.appURL.path)")
        }
        if let version = ProfileApps.claudeVersion { print("Claude \(version)") }
    }

    static func add(_ args: inout Arguments, adoptDefault: Bool) throws {
        let color = try args.option("--color")
        guard let name = args.first else { throw ProfileError("Missing profile name.") }
        var registry = Registry.load()
        let profile = try registry.add(name: name, color: color, adoptDefault: adoptDefault)
        if !profile.isDefault {
            print("Building \(profile.appName)…")
            try ProfileApps.build(profile)
        }
        print("Added \(profile.name) (\(profile.color)). Open it from Spotlight as \"\(profile.appName)\".")
    }

    static func open(_ args: Arguments) throws {
        try Updater.openAndWait(args.requireProfile())
    }

    static func quit(_ args: Arguments) throws {
        let profile = try args.requireProfile()
        print(ProfileApps.quit(profile) ? "Asked \(profile.appName) to quit." : "\(profile.appName) is not running.")
    }

    static func update(_ args: inout Arguments) throws {
        let restart = args.flag("--restart")
        let force = args.flag("--force")
        let registry = Registry.load()
        let profiles = args.first == nil ? registry.profiles : [try args.requireProfile()]
        let outcome = Updater.update(profiles, restartRunning: restart, force: force) { print("Building \($0.appName)…") }
        report(outcome)
        if outcome.updated.isEmpty, outcome.waiting.isEmpty, outcome.failed.isEmpty {
            print("All profile apps match Claude \(ProfileApps.claudeVersion ?? "").")
        }
        if !outcome.failed.isEmpty { throw ProfileError("Some profiles could not be updated.") }
    }

    static func remove(_ args: inout Arguments) throws {
        let trashData = args.flag("--trash-data")
        let profile = try args.requireProfile()
        if !profile.isDefault, profile.runningApp != nil {
            throw ProfileError("Quit \(profile.appName) first.")
        }

        try ProfileApps.remove(profile)
        var registry = Registry.load()
        try registry.remove(profile)

        if trashData {
            if let dataDir = profile.dataDir {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: dataDir), resultingItemURL: nil)
                print("Moved \(dataDir) to the Trash.")
            } else {
                print("Kept the default Claude folder. Only the profile entry was removed.")
            }
        }
        print("Removed \(profile.name).")
    }

    static func installLoginItem() throws {
        try Installer.installLoginItem()
        print("The menu bar app will start at login.")
    }

    static func uninstallLoginItem() {
        Installer.uninstallLoginItem()
        print("Removed the login item.")
    }

    static func report(_ outcome: Updater.Outcome) {
        for profile in outcome.updated { print("Updated \(profile.appName).") }
        for profile in outcome.waiting {
            print("\(profile.appName) is running. Run `claude-profiles update --restart` to update it now.")
        }
        for (profile, error) in outcome.failed { print("Could not update \(profile.appName): \(error.localizedDescription)") }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
