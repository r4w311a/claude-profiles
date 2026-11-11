import Foundation

let arguments = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }

if Bundle.main.infoDictionary?[Installer.menuBarKey] as? Bool == true {
    MenuBarApp.run(arguments: arguments)
}
CLI.run(arguments)
