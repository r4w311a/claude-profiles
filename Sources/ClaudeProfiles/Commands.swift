import Foundation

enum Commands {
    static func list() {
        let registry = Registry.load()
        let instances = Instances.running()
        if registry.profiles.isEmpty {
            print("No profiles yet. Try `claude-profiles adopt-default Personal`.")
        }
        for profile in registry.profiles {
            let status = Instances.instance(for: profile, in: instances)
                .map { "running (pid \($0.pid))" } ?? "stopped"
            let location = profile.isDefault ? "(default folder)" : profile.resolvedDataDir
            print("\(pad(profile.name, 14)) \(pad(profile.color, 8)) \(pad(status, 22)) \(location)")
        }
        for instance in instances where Instances.profile(for: instance, in: registry) == nil {
            print("Unregistered Claude instance, pid \(instance.pid): \(instance.dataDir ?? "default folder")")
        }
    }

    static func add(_ args: inout Arguments, adoptDefault: Bool) throws {
        let color = try args.option("--color")
        guard let name = args.first else { throw ProfileError("Missing profile name.") }
        var registry = Registry.load()
        let profile = try registry.add(name: name, color: color, adoptDefault: adoptDefault)
        let launcher = try Bundles.writeLauncher(for: profile)
        print("Added \(profile.name) (\(profile.color)) at \(profile.resolvedDataDir)")
        print("Launcher: \(launcher.path)")
    }

    static func open(_ args: Arguments) throws {
        try Instances.open(args.requireProfile())
    }

    static func quit(_ args: Arguments) throws {
        let profile = try args.requireProfile()
        print(Instances.quit(profile) ? "Asked \(profile.name) to quit." : "\(profile.name) is not running.")
    }

    static func signIn(_ args: inout Arguments) throws {
        let skipPrompt = args.flag("--yes")
        let profile = try args.requireProfile()
        let registry = Registry.load()
        let others = Instances.others(than: profile)

        if !others.isEmpty {
            let names = others.map { Instances.displayName($0, in: registry) }.joined(separator: ", ")
            print("Google sign-in returns through a claude:// link, which macOS may hand to the wrong Claude window.")
            print("To sign in to \(profile.name), these will quit and reopen afterwards: \(names)")
            if !skipPrompt {
                print("Continue? [y/N] ", terminator: "")
                guard readLine()?.lowercased().hasPrefix("y") == true else {
                    print("Cancelled.")
                    return
                }
            }
            try Instances.quitForSignIn(others, registry: registry)
        }

        try Instances.open(profile)
        print("Sign in inside the Claude \(profile.name) window, then press Return here… ", terminator: "")
        _ = readLine()
        Instances.relaunch(others)
        if !others.isEmpty { print("Reopened \(others.count) other instance(s).") }
    }

    static func remove(_ args: inout Arguments) throws {
        let trashData = args.flag("--trash-data")
        let profile = try args.requireProfile()
        if trashData, Instances.instance(for: profile) != nil {
            throw ProfileError("Quit \(profile.name) before trashing its data.")
        }

        var registry = Registry.load()
        registry.profiles.removeAll { $0.slug == profile.slug }
        try registry.save()
        Bundles.removeLauncher(for: profile)

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

    static func install() throws {
        let fileManager = FileManager.default
        let source = Bundles.currentExecutable
        let target = Paths.installedBinary
        if source.path != target.resolvingSymlinksInPath().path {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: source, to: target)
            print("Installed \(target.path)")
        }
        try Bundles.writeMenuBarApp()
        print("Menu bar app: \(Paths.menuBarApp.path)")
        for profile in Registry.load().profiles {
            print("Launcher: \(try Bundles.writeLauncher(for: profile).path)")
        }
    }

    static func installAgent() throws {
        try Bundles.installAgent()
        print("The menu bar app will start at login (\(Paths.launchAgent.path)).")
    }

    static func uninstallAgent() {
        Bundles.uninstallAgent()
        print("Removed the login agent.")
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
