import AppKit
import Foundation

let usage = """
claude-profiles: run several Claude Desktop accounts side by side.

Usage:
  claude-profiles list
  claude-profiles add <name> [--color <color>]
  claude-profiles adopt-default <name> [--color <color>]   register Claude's existing data folder
  claude-profiles open <name>                              focus if running, otherwise launch
  claude-profiles quit <name>
  claude-profiles remove <name> [--trash-data]
  claude-profiles install                                  copy binary to ~/.local/bin, rebuild apps
  claude-profiles menubar
  claude-profiles install-agent | uninstall-agent          start the menu bar app at login

Colors: \(Palette.names.joined(separator: ", "))
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func option(_ name: String, in args: inout [String]) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    guard i + 1 < args.count else { fail("\(name) needs a value") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

func flag(_ name: String, in args: inout [String]) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func requireProfile(_ query: String?) -> Profile {
    guard let query else { fail("missing profile name\n\n\(usage)") }
    guard let profile = Registry.load().find(query) else {
        fail("no profile named \"\(query)\". Run `claude-profiles list`.")
    }
    return profile
}

func addProfile(_ args: inout [String], adoptDefault: Bool) throws {
    let color = option("--color", in: &args)
    guard let name = args.first else { fail("missing profile name") }
    var registry = Registry.load()
    let profile = try registry.add(name: name, color: color, adoptDefault: adoptDefault)
    let launcher = try Bundles.writeLauncher(for: profile)
    print("Added \(profile.name) (\(profile.color)) → \(profile.resolvedDataDir)")
    print("Launcher: \(launcher.path)")
}

func list() {
    let registry = Registry.load()
    let instances = Instances.running()
    if registry.profiles.isEmpty { print("No profiles yet. Try `claude-profiles adopt-default Personal`.") }
    for p in registry.profiles {
        let pid = Instances.instance(for: p, in: instances).map { "running (pid \($0.pid))" } ?? "stopped"
        let name = p.name.padding(toLength: 14, withPad: " ", startingAt: 0)
        let color = p.color.padding(toLength: 8, withPad: " ", startingAt: 0)
        let status = pid.padding(toLength: 22, withPad: " ", startingAt: 0)
        print("\(name) \(color) \(status) \(p.isDefault ? "(default folder)" : p.resolvedDataDir)")
    }
    let unknown = instances.filter { Instances.profile(for: $0, in: registry) == nil }
    for i in unknown { print("unregistered Claude instance, pid \(i.pid): \(i.dataDir ?? "default folder")") }
}

func install() throws {
    let fm = FileManager.default
    let source = Bundles.currentExecutable
    if source.path != Paths.installedBinary.resolvingSymlinksInPath().path {
        try fm.createDirectory(at: Paths.installedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: Paths.installedBinary.path) { try fm.removeItem(at: Paths.installedBinary) }
        try fm.copyItem(at: source, to: Paths.installedBinary)
        print("Installed \(Paths.installedBinary.path)")
    }
    try Bundles.writeMenuBarApp()
    print("Menu bar app: \(Paths.menuBarApp.path)")
    for profile in Registry.load().profiles {
        print("Launcher: \(try Bundles.writeLauncher(for: profile).path)")
    }
}

func runLauncher(slug: String) -> Never {
    do {
        guard let profile = Registry.load().find(slug) else {
            throw ProfileError("The Claude profile \"\(slug)\" no longer exists.")
        }
        try Instances.open(profile)
    } catch {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
        exit(1)
    }
    exit(0)
}

// MARK: - Entry point

var args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }
let info = Bundle.main.infoDictionary ?? [:]

if args.isEmpty, let slug = info[Bundles.profileKey] as? String { runLauncher(slug: slug) }
if args.isEmpty, info[Bundles.menuBarKey] as? Bool == true { MenuBarController.run() }

let command = args.isEmpty ? "help" : args.removeFirst()
do {
    switch command {
    case "list", "ls":
        list()
    case "add":
        try addProfile(&args, adoptDefault: false)
    case "adopt-default":
        try addProfile(&args, adoptDefault: true)
    case "open":
        try Instances.open(requireProfile(args.first))
    case "quit":
        let profile = requireProfile(args.first)
        print(Instances.quit(profile) ? "Asked \(profile.name) to quit." : "\(profile.name) isn't running.")
    case "remove", "rm":
        let trashData = flag("--trash-data", in: &args)
        let profile = requireProfile(args.first)
        if trashData, Instances.instance(for: profile) != nil { fail("quit \(profile.name) before trashing its data") }
        var registry = Registry.load()
        registry.profiles.removeAll { $0.slug == profile.slug }
        try registry.save()
        Bundles.removeLauncher(for: profile)
        if trashData {
            if profile.isDefault {
                print("Kept the default Claude folder; only the profile entry was removed.")
            } else if let dir = profile.dataDir {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)
                print("Moved \(dir) to the Trash.")
            }
        }
        print("Removed \(profile.name).")
    case "install":
        try install()
    case "menubar":
        MenuBarController.run()
    case "install-agent":
        try Bundles.installAgent()
        print("The menu bar app will start at login (\(Paths.launchAgent.path)).")
    case "uninstall-agent":
        Bundles.uninstallAgent()
        print("Removed the login agent.")
    case "help", "-h", "--help":
        print(usage)
    default:
        fail("unknown command \"\(command)\"\n\n\(usage)")
    }
} catch {
    fail(error.localizedDescription)
}
