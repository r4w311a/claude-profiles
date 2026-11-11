import AppKit
import Foundation

struct Profile: Codable, Equatable {
    var slug: String
    var name: String
    var color: String
    var dataDir: String?

    var isDefault: Bool { dataDir == nil }
    var resolvedDataDir: String { dataDir ?? Paths.defaultData.path }
    var nsColor: NSColor { Palette.color(named: color) }
    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    var appName: String { isDefault ? "Claude" : "Claude \(name)" }
    var bundleID: String { isDefault ? Paths.claudeBundleID : "local.claude-profiles.\(slug)" }
    var appURL: URL {
        isDefault ? Paths.claudeApp : Paths.profileApps.appendingPathComponent("\(appName).app")
    }

    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated && $0.processIdentifier > 0 }
    }

    func badge(size: CGFloat = 16, alpha: CGFloat = 1) -> NSImage {
        Palette.badge(initial, color: nsColor, size: size, alpha: alpha)
    }
}

struct ProfileError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct Registry {
    var profiles: [Profile] = []

    static func load() -> Registry {
        guard let data = try? Data(contentsOf: Paths.registry),
              let profiles = try? JSONDecoder().decode([Profile].self, from: data)
        else { return Registry() }
        return Registry(profiles: profiles)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Paths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: Paths.registry, options: .atomic)
    }

    func find(_ query: String) -> Profile? {
        let lowered = query.lowercased()
        return profiles.first { $0.slug == slugify(query) || $0.name.lowercased() == lowered }
    }

    func profile(forBundleID bundleID: String?) -> Profile? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }
    }

    mutating func add(name: String, color: String?, adoptDefault: Bool = false) throws -> Profile {
        let slug = slugify(name)
        guard !slug.isEmpty else { throw ProfileError("Profile name needs at least one letter or digit.") }
        guard find(name) == nil else { throw ProfileError("A profile named \"\(name)\" already exists.") }
        if adoptDefault, profiles.contains(where: \.isDefault) {
            throw ProfileError("The default Claude folder is already registered as a profile.")
        }
        if let color, !Palette.names.contains(color.lowercased()) {
            throw ProfileError("Unknown color \"\(color)\". Choose one of: \(Palette.names.joined(separator: ", ")).")
        }

        var dataDir: String?
        if !adoptDefault {
            let dir = Paths.root.appendingPathComponent(slug)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dataDir = dir.path
        }
        let used = Set(profiles.map(\.color))
        let pick = color?.lowercased() ?? Palette.names.first { !used.contains($0) } ?? "gray"
        let profile = Profile(slug: slug, name: name, color: pick, dataDir: dataDir)
        profiles.append(profile)
        try save()
        return profile
    }

    mutating func remove(_ profile: Profile) throws {
        profiles.removeAll { $0.slug == profile.slug }
        try save()
    }
}

func slugify(_ text: String) -> String {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}
