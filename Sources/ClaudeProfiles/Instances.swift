import AppKit
import Darwin
import Foundation

/// A running Claude Desktop main process and the data folder it was started with.
struct Instance {
    let app: NSRunningApplication
    /// Normalized --user-data-dir value, or nil when launched without one (the default folder).
    let dataDir: String?

    var pid: pid_t { app.processIdentifier }
}

enum Instances {
    /// Every running Claude Desktop main process. Helper processes have their own bundle IDs, so they're excluded.
    static func running() -> [Instance] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == Paths.claudeBundleID && !$0.isTerminated }
            .map { Instance(app: $0, dataDir: userDataDir(of: $0.processIdentifier)) }
    }

    static func instance(for profile: Profile, in instances: [Instance] = running()) -> Instance? {
        instances.first { matches(profile, $0) }
    }

    static func profile(for instance: Instance, in registry: Registry) -> Profile? {
        registry.profiles.first { matches($0, instance) }
    }

    static func matches(_ profile: Profile, _ instance: Instance) -> Bool {
        switch (profile.dataDir, instance.dataDir) {
        case (nil, nil): return true
        case let (p?, i?): return normalize(p) == i
        default: return false
        }
    }

    static func launch(_ profile: Profile) throws {
        try launch(dataDir: profile.dataDir)
    }

    static func launch(dataDir: String?) throws {
        var args = ["-n", "-a", Paths.claudeApp.path]
        if let dir = dataDir {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            args += ["--args", "--user-data-dir=\(dir)"]
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = args
        try open.run()
        open.waitUntilExit()
        guard open.terminationStatus == 0 else { throw ProfileError("Couldn't launch Claude (open exited \(open.terminationStatus)).") }
    }

    /// Brings the instance to the front, launching the profile if it isn't running.
    static func open(_ profile: Profile) throws {
        if let instance = instance(for: profile) {
            focus(instance.app)
        } else {
            try launch(profile)
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

    // MARK: - Sign-in

    // Google sign-in finishes in the system browser, which hands the result back through a claude:// link.
    // macOS delivers that link to one Claude instance of its choosing, and only the instance that started
    // the login (it holds the matching hop_nonce) accepts it. So during sign-in, the target must be alone.

    /// Every running instance except the profile's own.
    static func others(than profile: Profile) -> [Instance] {
        running().filter { !matches(profile, $0) }
    }

    /// Asks the instances to quit and waits for them to exit. Returns the ones still running at the timeout.
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

    /// Relaunches instances closed by `quitAndWait`, each with the data folder it had.
    static func relaunch(_ instances: [Instance]) {
        for instance in instances { try? launch(dataDir: instance.dataDir) }
    }

    // MARK: - Process arguments

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func userDataDir(of pid: pid_t) -> String? {
        guard let args = arguments(of: pid) else { return nil }
        for (i, arg) in args.enumerated() {
            if arg.hasPrefix("--user-data-dir=") {
                return normalize(String(arg.dropFirst("--user-data-dir=".count)))
            }
            if arg == "--user-data-dir", i + 1 < args.count {
                return normalize(args[i + 1])
            }
        }
        return nil
    }

    /// Reads a process's argv via sysctl(KERN_PROCARGS2), so paths containing spaces survive intact.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }

        let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 } // executable path
        while i < size, buf[i] == 0 { i += 1 } // padding

        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buf[i] != 0 { i += 1 }
            args.append(String(decoding: buf[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}
