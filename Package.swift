// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claude-profiles",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "claude-profiles", path: "Sources/ClaudeProfiles"),
        .executableTarget(
            name: "claude-profile-launcher",
            path: "Sources/Launcher",
            linkerSettings: [.linkedFramework("CoreFoundation")]
        ),
    ]
)
