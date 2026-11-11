import AppKit

final class MenuBarApp: NSObject, NSApplicationDelegate {
    static let backgroundFlag = "--background"

    private let launchedInBackground: Bool
    private var model: AppModel?
    private var menuBar: MenuBarController?
    private var window: ProfilesWindowController?

    init(launchedInBackground: Bool) {
        self.launchedInBackground = launchedInBackground
    }

    static func run(arguments: [String]) -> Never {
        let app = NSApplication.shared
        let delegate = MenuBarApp(launchedInBackground: arguments.contains(backgroundFlag))
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        let window = ProfilesWindowController(model: model)
        self.model = model
        self.window = window
        menuBar = MenuBarController(model: model) { [weak window] in window?.show() }

        if launchedInBackground {
            if model.openProfilesAtLogin { model.openAllInBackground() }
        } else {
            window.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
