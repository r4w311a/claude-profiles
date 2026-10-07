import AppKit
import Darwin
import Foundation

struct Instance {
    let app: NSRunningApplication
    let dataDir: String?

    var pid: pid_t { app.processIdentifier }
}

enum Instances {
    static func running() -> [Instance] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == Paths.claudeBundleID && !$0.isTerminated }
            .map { Instance(app: $0, dataDir: ProcessArguments.userDataDir(of: $0.processIdentifier)) }
    }

    static func instance(for profile: Profile, in instances: [Instance] = running()) -> Instance? {
        instances.first { matches(profile, $0) }
    }

    static func profile(for instance: Instance, in registry: Registry) -> Profile? {
        registry.profiles.first { matches($0, instance) }
    }

    static func others(than profile: Profile) -> [Instance] {
        running().filter { !matches(profile, $0) }
    }

    static func displayName(_ instance: Instance, in registry: Registry) -> String {
        profile(for: instance, in: registry)?.name ?? "pid \(instance.pid)"
    }

    static func matches(_ profile: Profile, _ instance: Instance) -> Bool {
        switch (profile.dataDir, instance.dataDir) {
        case (nil, nil): return true
        case let (profileDir?, instanceDir?): return ProcessArguments.normalize(profileDir) == instanceDir
        default: return false
        }
    }

    static func open(_ profile: Profile) throws {
        if let instance = instance(for: profile) {
            focus(instance.app)
        } else {
            try launch(dataDir: profile.dataDir)
        }
    }

    static func launch(dataDir: String?) throws {
        var arguments = ["-n", "-a", Paths.claudeApp.path]
        if let dataDir {
            try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
            arguments += ["--args", "\(ProcessArguments.dataDirFlag)=\(dataDir)"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProfileError("Could not launch Claude (open exited with \(process.terminationStatus)).")
        }
    }

    static func focus(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            NSApplication.shared.yieldActivation(to: app)
            if app.activate(from: .current, options: [.activateAllWindows]) { return }
        }
        app.activate(options: [.activateAllWindows])
    }

    static func quit(_ profile: Profile) -> Bool {
        guard let instance = instance(for: profile) else { return false }
        return instance.app.terminate()
    }

    static func quitForSignIn(_ instances: [Instance], registry: Registry) throws {
        let stuck = quitAndWait(instances)
        guard !stuck.isEmpty else { return }

        let stuckPIDs = Set(stuck.map(\.pid))
        relaunch(instances.filter { !stuckPIDs.contains($0.pid) })
        let names = stuck.map { displayName($0, in: registry) }.joined(separator: ", ")
        throw ProfileError("\(names) did not quit. It may be waiting on a confirmation dialog. Quit it and try again.")
    }

    static func quitAndWait(_ instances: [Instance], timeout: TimeInterval = 20) -> [Instance] {
        for instance in instances { instance.app.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        var remaining = instances
        while !remaining.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            remaining.removeAll { kill($0.pid, 0) != 0 }
        }
        return remaining
    }

    static func relaunch(_ instances: [Instance]) {
        for instance in instances { try? launch(dataDir: instance.dataDir) }
    }
}
