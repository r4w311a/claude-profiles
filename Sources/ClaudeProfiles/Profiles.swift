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

func slugify(_ text: String) -> String {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}
