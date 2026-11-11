import Foundation

enum Commands {
    static func list() {
        let registry = Registry.load()
        if registry.profiles.isEmpty {
            print("No profiles yet. Try `claude-profiles adopt-default Personal`.")
        }
        for profile in registry.profiles {
            let running = profile.running.map { "running (pid \($0.pid))" } ?? "stopped"
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
        print(ProfileApps.quit(profile) != nil ? "Asked \(profile.appName) to quit." : "\(profile.appName) is not running.")
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
        let skipConfirm = args.flag("--yes")
        let skipBackup = args.flag("--no-backup")
        let profile = try args.requireProfile()
        if !profile.isDefault, profile.runningApp != nil {
            throw ProfileError("Quit \(profile.appName) first.")
        }

        if trashData, profile.dataDir != nil {
            print(Backups.lossSummary)
            if !skipConfirm, !Backups.confirm("Type \(profile.name) to confirm:", expecting: profile.name) {
                print("Cancelled. Nothing was removed.")
                return
            }
            if !skipBackup {
                print("Backing up \(profile.name) first…")
                print("Saved \(try Backups.create(for: profile).path)")
            }
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

    static func backup(_ args: inout Arguments) throws {
        let force = args.flag("--force")
        let profile = try args.requireProfile()
        if profile.running != nil, !force {
            throw ProfileError("Quit \(profile.appName) first so the backup is complete, or add --force.")
        }
        print("Backing up \(profile.name)…")
        print("Saved \(try Backups.create(for: profile).path)")
    }

    static func restore(_ args: inout Arguments) throws {
        let skipConfirm = args.flag("--yes")
        let profile = try args.requireProfile()
        let archive: URL
        if args.values.count > 1 {
            archive = URL(fileURLWithPath: (args.values[1] as NSString).expandingTildeInPath)
        } else if let latest = Backups.list(named: profile.name).first {
            archive = latest
        } else {
            throw ProfileError("No backups found for \(profile.name) in \(Paths.backups.path).")
        }
        guard FileManager.default.fileExists(atPath: archive.path) else {
            throw ProfileError("\(archive.path) does not exist.")
        }

        print("Restore \(profile.name) from \(archive.lastPathComponent)? Its current data moves to the Trash.")
        if !skipConfirm, !Backups.confirm("Type \(profile.name) to confirm:", expecting: profile.name) {
            print("Cancelled. Nothing was changed.")
            return
        }
        try Backups.restore(profile, from: archive)
        print("Restored \(profile.name). Open it with `claude-profiles open \(profile.name)`.")
    }

    static func listBackups(_ args: Arguments) throws {
        let name = args.first.map { Registry.load().find($0)?.name ?? $0 }
        let backups = Backups.list(named: name)
        if backups.isEmpty { print("No backups yet in \(Paths.backups.path).") }
        for backup in backups {
            let size = (try? backup.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            print("\(backup.lastPathComponent)  \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
        }
    }

    static func uninstall(_ args: inout Arguments) throws {
        let removeData = args.flag("--all")
        let skipConfirm = args.flag("--yes")
        let skipBackup = args.flag("--no-backup")
        if removeData {
            print("This removes every profile app and all profile data. \(Backups.lossSummary)")
            if !skipBackup { print("Each profile is backed up to \(Paths.backups.path) first.") }
            if !skipConfirm, !Backups.confirm("Type DELETE to confirm:", expecting: "DELETE") {
                print("Cancelled. Nothing was removed.")
                return
            }
        }
        try Installer.uninstall(removeData: removeData, backUpFirst: !skipBackup)
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
