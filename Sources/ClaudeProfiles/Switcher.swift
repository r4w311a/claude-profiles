import AppKit
import CoreGraphics

enum Switcher {
    static func activate(_ profile: Profile, completion: @escaping (Error?) -> Void) {
        guard let (app, pid) = profile.running else {
            ProfileApps.open(profile, completion: completion)
            return
        }
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateAllWindows])
        guard !hasVisibleWindow(pid) else {
            completion(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: profile.appURL, configuration: configuration) { _, error in
            completion(error)
        }
    }

    static func launchInBackground(_ profile: Profile) {
        guard profile.runningApp == nil else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        NSWorkspace.shared.openApplication(at: profile.appURL, configuration: configuration) { _, _ in }
    }

    private static func hasVisibleWindow(_ pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
    }
}
