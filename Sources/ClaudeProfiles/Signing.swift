import Foundation

enum Signing {
    static let codesign = "/usr/bin/codesign"
    static let preferredIdentity = "Claude Profiles"
    static let restrictedEntitlements = [
        "com.apple.application-identifier",
        "com.apple.developer.team-identifier",
        "keychain-access-groups",
    ]

    static let identity: String = {
        let result = Shell.run("/usr/bin/security", ["find-identity", "-p", "codesigning"])
        let listing = String(decoding: result.output, as: UTF8.self)
        return listing.contains("\"\(preferredIdentity)\"") ? preferredIdentity : "-"
    }()

    static func profileEntitlements(from app: URL) throws -> [String: Any] {
        let result = Shell.run(codesign, ["-d", "--entitlements", "-", "--xml", app.path])
        guard result.succeeded,
              let plist = try? PropertyListSerialization.propertyList(from: result.output, format: nil),
              var entitlements = plist as? [String: Any]
        else { throw ProfileError("Could not read Claude's entitlements: \(result.error)") }
        for key in restrictedEntitlements { entitlements.removeValue(forKey: key) }
        entitlements["com.apple.security.cs.disable-library-validation"] = true
        return entitlements
    }

    static func sign(_ url: URL, entitlements: [String: Any]? = nil) throws {
        var entitlementsFile: URL?
        if let entitlements {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("claude-profiles-\(UUID().uuidString).plist")
            try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: file)
            entitlementsFile = file
        }
        defer { entitlementsFile.map { try? FileManager.default.removeItem(at: $0) } }

        func attempt(_ identity: String) -> Shell.Result {
            var arguments = ["--force", "--sign", identity, "--options", "runtime"]
            if let entitlementsFile { arguments += ["--entitlements", entitlementsFile.path] }
            return Shell.run(codesign, arguments + [url.path])
        }

        var result = attempt(identity)
        if !result.succeeded, identity != "-" { result = attempt("-") }
        guard result.succeeded else { throw ProfileError("Signing \(url.lastPathComponent) failed: \(result.error)") }
    }
}
