import Foundation

enum Updater {
    struct Outcome {
        var updated: [Profile] = []
        var waiting: [Profile] = []
        var failed: [(Profile, Error)] = []
    }

    static func pending(in registry: Registry = .load()) -> [Profile] {
        registry.profiles.filter { !$0.isDefault && ProfileApps.needsBuild($0) }
    }

    static func update(_ profiles: [Profile], restartRunning: Bool, force: Bool = false,
                       progress: (Profile) -> Void = { _ in }) -> Outcome {
        var outcome = Outcome()
        for profile in profiles where !profile.isDefault && (force || ProfileApps.needsBuild(profile)) {
            let wasRunning = profile.runningApp != nil
            if wasRunning {
                guard restartRunning else {
                    outcome.waiting.append(profile)
                    continue
                }
                guard ProfileApps.quitAndWait(profile) else {
                    outcome.failed.append((profile, ProfileError("\(profile.appName) did not quit.")))
                    continue
                }
            }
            progress(profile)
            do {
                try ProfileApps.build(profile)
                outcome.updated.append(profile)
                if wasRunning { try openAndWait(profile) }
            } catch {
                outcome.failed.append((profile, error))
            }
        }
        return outcome
    }

    static func openAndWait(_ profile: Profile) throws {
        let done = DispatchSemaphore(value: 0)
        var failure: Error?
        ProfileApps.open(profile) { error in
            failure = error
            done.signal()
        }
        done.wait()
        if let failure { throw failure }
    }
}
