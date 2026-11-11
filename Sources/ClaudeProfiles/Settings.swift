import Foundation

enum Settings {
    private static let openProfilesAtLoginKey = "OpenProfilesAtLogin"

    static var openProfilesAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: openProfilesAtLoginKey) }
        set { UserDefaults.standard.set(newValue, forKey: openProfilesAtLoginKey) }
    }
}
