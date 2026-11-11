import AppKit
import Combine

final class AppModel: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var runningSlugs: Set<String> = []
    @Published private(set) var pendingSlugs: Set<String> = []
    @Published private(set) var buildingSlugs: Set<String> = []
    @Published private(set) var failures: [String: String] = [:]
    @Published private(set) var frontSlug: String?
    @Published private(set) var activeSlug: String?
    @Published private(set) var claudeVersion: String?
    @Published private(set) var startsAtLogin = Installer.isLoginItemInstalled
    @Published var openProfilesAtLogin = Settings.openProfilesAtLogin {
        didSet { Settings.openProfilesAtLogin = openProfilesAtLogin }
    }
    @Published var isAddingProfile = false
    @Published private(set) var hoveredSlug: String?

    private var previousSlug: String?
    private var icons: [String: NSImage] = [:]
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var exitWatchers: [pid_t: DispatchSourceProcess] = [:]
    private var updateTimer: Timer?
    private let hotKeys = HotKeys()
    private let buildQueue = DispatchQueue(label: "local.claude-profiles.build", qos: .userInitiated)

    var isUpdating: Bool { !buildingSlugs.isEmpty }

    init() {
        reloadProfiles()
        frontSlug = slug(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        activeSlug = frontSlug

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appLaunched), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        watch(Paths.root) { [weak self] in self?.reloadProfiles() }
        watch(Paths.claudeApp.deletingLastPathComponent()) { [weak self] in self?.claudeMayHaveChanged() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.updateIdleProfiles()
        }
        updateIdleProfiles()
    }

    func setHovered(_ slug: String, _ hovering: Bool) {
        if hovering { hoveredSlug = slug } else if hoveredSlug == slug { hoveredSlug = nil }
    }

    func profile(_ slug: String) -> Profile? {
        profiles.first { $0.slug == slug }
    }

    func shortcut(for profile: Profile) -> String? {
        guard let index = profiles.firstIndex(of: profile), index < HotKeys.digitKeyCodes.count else { return nil }
        return "\(HotKeys.symbol)\(index + 1)"
    }

    func icon(for profile: Profile) -> NSImage {
        if let icon = icons[profile.slug] { return icon }
        let icon = FileManager.default.fileExists(atPath: profile.appURL.path)
            ? NSWorkspace.shared.icon(forFile: profile.appURL.path)
            : profile.badge(size: 64)
        icons[profile.slug] = icon
        return icon
    }

    var suggestedColor: String {
        let used = Set(profiles.map(\.color))
        return Palette.names.first { !used.contains($0) } ?? "gray"
    }

    var statusLine: String {
        let version = claudeVersion.map { "Claude \($0)" } ?? "Claude is not installed"
        if isUpdating {
            let names = profiles.filter { buildingSlugs.contains($0.slug) }.map(\.name)
            return "\(version) · Updating \(names.joined(separator: ", "))…"
        }
        switch pendingSlugs.count {
        case 0: return "\(version) · All profiles up to date"
        case 1: return "\(version) · 1 profile needs an update"
        default: return "\(version) · \(pendingSlugs.count) profiles need an update"
        }
    }

    func switchTo(_ slug: String) {
        guard let profile = profile(slug), !buildingSlugs.contains(slug) else { return }
        guard profile.runningApp == nil, ProfileApps.needsBuild(profile) else {
            Switcher.activate(profile) { [weak self] error in self?.report(error) }
            return
        }
        buildingSlugs.insert(slug)
        buildQueue.async { [weak self] in
            let result = Result { try ProfileApps.build(profile) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.buildingSlugs.remove(slug)
                self.icons.removeValue(forKey: slug)
                self.refreshPending()
                switch result {
                case .success: Switcher.activate(profile) { [weak self] error in self?.report(error) }
                case .failure(let error): self.report(error)
                }
            }
        }
    }

    func switchToPrevious() {
        let target = frontSlug == nil ? activeSlug : previousSlug
        if let target { switchTo(target) }
    }

    func quit(_ slug: String) {
        if let profile = profile(slug) { ProfileApps.quit(profile) }
    }

    func updateAll() {
        let pending = profiles.filter { pendingSlugs.contains($0.slug) && !buildingSlugs.contains($0.slug) }
        let running = pending.filter { $0.runningApp != nil }
        if !running.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Update open profiles?"
            alert.informativeText = "\(running.map(\.appName).joined(separator: ", ")) will quit, update to "
                + "Claude \(claudeVersion ?? "") and open again. Running Claude Code sessions in them will stop."
            alert.addButton(withTitle: "Update and Reopen")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        rebuild(pending, restartRunning: true, force: false)
    }

    func rebuild(_ slug: String) {
        guard let profile = profile(slug), !profile.isDefault else { return }
        rebuild([profile], restartRunning: true, force: true)
    }

    var hasDefaultProfile: Bool {
        profiles.contains(where: \.isDefault)
    }

    func add(name: String, color: String, isCurrentAccount: Bool) throws {
        var registry = Registry.load()
        let profile = try registry.add(name: name, color: color, adoptDefault: isCurrentAccount)
        reloadProfiles()
        switchTo(profile.slug)
    }

    func setColor(_ color: String, for slug: String) {
        var registry = Registry.load()
        guard let index = registry.profiles.firstIndex(where: { $0.slug == slug }) else { return }
        registry.profiles[index].color = color
        do {
            try registry.save()
            icons.removeValue(forKey: slug)
            reloadProfiles()
            updateIdleProfiles()
        } catch {
            report(error)
        }
    }

    func confirmRemove(_ slug: String) {
        guard let profile = profile(slug) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(profile.name)?"
        alert.informativeText = profile.isDefault
            ? "The original Claude app and its data stay as they are. Only the profile entry is removed."
            : "\(profile.appName) moves to the Trash. Its login and chats stay in its data folder unless you trash that too."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if !profile.isDefault {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Also move its data folder to the Trash"
        }
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if !profile.isDefault, profile.running != nil {
                ProfileApps.quit(profile)
                throw ProfileError("\(profile.appName) was still open. It is quitting now, try removing it again in a moment.")
            }
            try ProfileApps.remove(profile)
            var registry = Registry.load()
            try registry.remove(profile)
            if alert.suppressionButton?.state == .on, let dataDir = profile.dataDir {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: dataDir), resultingItemURL: nil)
            }
            icons.removeValue(forKey: slug)
            reloadProfiles()
        } catch {
            report(error)
        }
    }

    func reveal(_ slug: String) {
        guard let profile = profile(slug) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([profile.appURL])
    }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            if enabled { try Installer.installLoginItem() } else { Installer.uninstallLoginItem() }
        } catch {
            report(error)
        }
        startsAtLogin = Installer.isLoginItemInstalled
    }

    func openAllInBackground() {
        for profile in profiles where profile.runningApp == nil && !ProfileApps.needsBuild(profile) {
            Switcher.launchInBackground(profile)
        }
    }

    private func reloadProfiles() {
        let loaded = Registry.load().profiles
        if loaded != profiles { profiles = loaded }
        refreshRunning()
        refreshPending()
        bindHotKeys()
    }

    private func refreshRunning() {
        var running: Set<String> = []
        var pids: Set<pid_t> = []
        for profile in profiles {
            guard let pid = profile.running?.pid else { continue }
            running.insert(profile.slug)
            pids.insert(pid)
        }
        if running != runningSlugs { runningSlugs = running }
        watchExits(of: pids)
    }

    private func watchExits(of pids: Set<pid_t>) {
        for pid in Set(exitWatchers.keys).subtracting(pids) {
            exitWatchers.removeValue(forKey: pid)?.cancel()
        }
        for pid in pids where exitWatchers[pid] == nil {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak self] in self?.profileExited(pid) }
            source.resume()
            exitWatchers[pid] = source
        }
    }

    private func profileExited(_ pid: pid_t) {
        exitWatchers.removeValue(forKey: pid)?.cancel()
        refreshRunning()
        updateIdleProfiles()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.updateIdleProfiles() }
    }

    private func refreshPending() {
        claudeVersion = ProfileApps.claudeVersion
        let pending = Set(profiles.filter { !$0.isDefault && ProfileApps.needsBuild($0) }.map(\.slug))
        if pending != pendingSlugs { pendingSlugs = pending }
    }

    private func bindHotKeys() {
        var bindings = profiles.prefix(HotKeys.digitKeyCodes.count).enumerated().map { index, profile in
            HotKeys.Binding(keyCode: HotKeys.digitKeyCodes[index]) { [weak self] in self?.switchTo(profile.slug) }
        }
        bindings.append(HotKeys.Binding(keyCode: HotKeys.previousKeyCode) { [weak self] in self?.switchToPrevious() })
        hotKeys.bind(bindings)
    }

    private func slug(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        return profiles.first { $0.bundleID == bundleID }?.slug
    }

    private func bundleID(in note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    @objc private func appActivated(_ note: Notification) {
        let slug = slug(forBundleID: bundleID(in: note))
        if let slug, slug != activeSlug {
            previousSlug = activeSlug
            activeSlug = slug
        }
        if bundleID(in: note) != Installer.menuBarBundleID { frontSlug = slug }
        if let slug, !runningSlugs.contains(slug) { refreshRunning() }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard slug(forBundleID: bundleID(in: note)) != nil else { return }
        refreshRunning()
        for delay in [0.5, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshRunning() }
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard slug(forBundleID: bundleID(in: note)) != nil else { return }
        refreshRunning()
        updateIdleProfiles()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.updateIdleProfiles() }
    }

    private func claudeMayHaveChanged() {
        guard ProfileApps.claudeVersion != claudeVersion else { return }
        icons.removeAll()
        refreshPending()
        updateIdleProfiles()
    }

    private func updateIdleProfiles() {
        refreshPending()
        let idle = profiles.filter {
            pendingSlugs.contains($0.slug) && !buildingSlugs.contains($0.slug) && $0.runningApp == nil
        }
        if !idle.isEmpty { rebuild(idle, restartRunning: false, force: false) }
    }

    private func rebuild(_ targets: [Profile], restartRunning: Bool, force: Bool) {
        guard !targets.isEmpty else { return }
        let slugs = Set(targets.map(\.slug))
        buildingSlugs.formUnion(slugs)
        buildQueue.async { [weak self] in
            let outcome = Updater.update(targets, restartRunning: restartRunning, force: force)
            DispatchQueue.main.async {
                guard let self else { return }
                self.buildingSlugs.subtract(slugs)
                for slug in slugs { self.icons.removeValue(forKey: slug) }
                for profile in outcome.updated { self.failures.removeValue(forKey: profile.slug) }
                for (profile, error) in outcome.failed { self.failures[profile.slug] = error.localizedDescription }
                self.refreshRunning()
                self.refreshPending()
            }
        }
    }

    private func watch(_ directory: URL, onChange: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename],
                                                               queue: .main)
        var pending: DispatchWorkItem?
        source.setEventHandler {
            pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watchers.append(source)
    }

    private func report(_ error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }
}
