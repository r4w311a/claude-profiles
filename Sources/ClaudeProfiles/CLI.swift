import Foundation

enum CLI {
    static let usage = """
    claude-profiles: run several Claude Desktop accounts side by side.

    Usage:
      claude-profiles list
      claude-profiles add <name> [--color <color>]
      claude-profiles adopt-default <name> [--color <color>]
      claude-profiles open <name>
      claude-profiles quit <name>
      claude-profiles update [<name>] [--restart] [--force]
      claude-profiles remove <name> [--trash-data] [--no-backup] [--yes]
      claude-profiles backup <name> [--force]
      claude-profiles restore <name> [<backup.zip>] [--yes]
      claude-profiles backups [<name>]
      claude-profiles install
      claude-profiles uninstall [--all] [--no-backup] [--yes]
      claude-profiles menubar
      claude-profiles install-agent
      claude-profiles uninstall-agent
      claude-profiles --version

    Colors: \(Palette.names.joined(separator: ", "))
    """

    static func run(_ arguments: [String]) -> Never {
        var args = Arguments(arguments)
        do {
            try dispatch(args.popCommand() ?? "help", &args)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func dispatch(_ command: String, _ args: inout Arguments) throws {
        switch command {
        case "list", "ls":
            Commands.list()
        case "add":
            try Commands.add(&args, adoptDefault: false)
        case "adopt-default":
            try Commands.add(&args, adoptDefault: true)
        case "open":
            try Commands.open(args)
        case "quit":
            try Commands.quit(args)
        case "update", "sync":
            try Commands.update(&args)
        case "remove", "rm":
            try Commands.remove(&args)
        case "install":
            try Installer.install()
        case "uninstall":
            try Commands.uninstall(&args)
        case "backup":
            try Commands.backup(&args)
        case "restore":
            try Commands.restore(&args)
        case "backups":
            try Commands.listBackups(args)
        case "menubar":
            MenuBarApp.run(arguments: args.values)
        case "install-agent":
            try Commands.installLoginItem()
        case "uninstall-agent":
            Commands.uninstallLoginItem()
        case "version", "--version", "-v":
            print(Version.current)
        case "help", "-h", "--help":
            print(usage)
        default:
            throw ProfileError("Unknown command \"\(command)\".\n\n\(usage)")
        }
    }
}
