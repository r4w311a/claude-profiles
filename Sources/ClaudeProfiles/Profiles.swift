import AppKit
import Foundation

struct Profile: Codable, Equatable {
    var slug: String
    var name: String
    var color: String
    /// nil means Claude's default data folder (launched without --user-data-dir).
    var dataDir: String?

    var isDefault: Bool { dataDir == nil }
    var resolvedDataDir: String { dataDir ?? Paths.defaultData.path }
    var nsColor: NSColor { Palette.color(named: color) }
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let appSupport = home.appendingPathComponent("Library/Application Support")
    static let root = appSupport.appendingPathComponent("Claude-Profiles")
    static let registry = root.appendingPathComponent("profiles.json")
    static let defaultData = appSupport.appendingPathComponent("Claude")
    static let launchers = home.appendingPathComponent("Applications/Claude Profiles")
    static let menuBarApp = home.appendingPathComponent("Applications/Claude Profiles.app")
    static let installedBinary = home.appendingPathComponent(".local/bin/claude-profiles")
    static let launchAgent = home.appendingPathComponent("Library/LaunchAgents/\(Bundles.agentLabel).plist")
    static let claudeApp = URL(fileURLWithPath: "/Applications/Claude.app")
    static let claudeBundleID = "com.anthropic.claudefordesktop"
}

enum Palette {
    static let colors: [(String, NSColor)] = [
        ("blue", .systemBlue), ("orange", .systemOrange), ("green", .systemGreen),
        ("purple", .systemPurple), ("red", .systemRed), ("pink", .systemPink),
        ("teal", .systemTeal), ("yellow", .systemYellow), ("indigo", .systemIndigo),
        ("mint", .systemMint), ("brown", .systemBrown), ("gray", .systemGray),
    ]
    static var names: [String] { colors.map(\.0) }

    static func color(named name: String) -> NSColor {
        colors.first { $0.0 == name.lowercased() }?.1 ?? .systemGray
    }

    static func dot(_ color: NSColor, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
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

    /// Matches by slug or case-insensitive display name.
    func find(_ query: String) -> Profile? {
        let q = query.lowercased()
        return profiles.first { $0.slug == slugify(query) || $0.name.lowercased() == q }
    }

    /// Creates the profile entry (and its data folder). Pass `adoptDefault` to register Claude's existing folder.
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
}

func slugify(_ s: String) -> String {
    let parts = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
    return parts.filter { !$0.isEmpty }.joined(separator: "-")
}
