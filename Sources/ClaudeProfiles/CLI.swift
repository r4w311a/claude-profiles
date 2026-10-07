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
      claude-profiles signin <name> [--yes]
      claude-profiles remove <name> [--trash-data]
      claude-profiles install
      claude-profiles menubar
      claude-profiles install-agent
      claude-profiles uninstall-agent

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
        case "signin":
            try Commands.signIn(&args)
        case "remove", "rm":
            try Commands.remove(&args)
        case "install":
            try Commands.install()
        case "menubar":
            MenuBarController.run()
        case "install-agent":
            try Commands.installAgent()
        case "uninstall-agent":
            Commands.uninstallAgent()
        case "help", "-h", "--help":
            print(usage)
        default:
            throw ProfileError("Unknown command \"\(command)\".\n\n\(usage)")
        }
    }
}
