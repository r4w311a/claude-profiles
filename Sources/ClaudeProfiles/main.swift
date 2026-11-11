import Foundation

let arguments = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }

if arguments.isEmpty, Bundle.main.infoDictionary?[Installer.menuBarKey] as? Bool == true {
    MenuBarController.run()
}
CLI.run(arguments)
