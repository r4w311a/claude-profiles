struct Arguments {
    private(set) var values: [String]

    var first: String? { values.first }

    init(_ values: [String]) {
        self.values = values
    }

    mutating func popCommand() -> String? {
        values.isEmpty ? nil : values.removeFirst()
    }

    mutating func flag(_ name: String) -> Bool {
        guard let index = values.firstIndex(of: name) else { return false }
        values.remove(at: index)
        return true
    }

    mutating func option(_ name: String) throws -> String? {
        guard let index = values.firstIndex(of: name) else { return nil }
        guard index + 1 < values.count else { throw ProfileError("\(name) needs a value.") }
        let value = values[index + 1]
        values.removeSubrange(index...(index + 1))
        return value
    }

    func requireProfile() throws -> Profile {
        guard let query = first else { throw ProfileError("Missing profile name.\n\n\(CLI.usage)") }
        guard let profile = Registry.load().find(query) else {
            throw ProfileError("No profile named \"\(query)\". Run `claude-profiles list`.")
        }
        return profile
    }
}
