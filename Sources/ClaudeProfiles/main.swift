import AppKit

func runLauncher(slug: String) -> Never {
    do {
        guard let profile = Registry.load().find(slug) else {
            throw ProfileError("The Claude profile \"\(slug)\" no longer exists.")
        }
        try Instances.open(profile)
        exit(0)
    } catch {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
        exit(1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-psn_") }
let bundleInfo = Bundle.main.infoDictionary ?? [:]

if arguments.isEmpty, let slug = bundleInfo[Bundles.profileKey] as? String {
    runLauncher(slug: slug)
}
if arguments.isEmpty, bundleInfo[Bundles.menuBarKey] as? Bool == true {
    MenuBarController.run()
}
CLI.run(arguments)
