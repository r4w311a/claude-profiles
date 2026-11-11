import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let hotKeys = HotKeys()
    private let buildQueue = DispatchQueue(label: "local.claude-profiles.build")
    private var building: Set<String> = []
    private var failures: [String: String] = [:]
    private var lastActiveSlug: String?
    private var syncTimer: Timer?

    override init() {
        super.init()
        menu.delegate = self
        item.menu = menu

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appLaunched), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.updateIdleProfiles()
        }

        bindHotKeys()
        updateTitle()
        updateIdleProfiles()
    }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = MenuBarController()
        withExtendedLifetime(controller) { app.run() }
        exit(0)
    }

    private func isClaude(_ note: Notification) -> Bool {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard let bundleID = app?.bundleIdentifier else { return false }
        return bundleID == Paths.claudeBundleID || bundleID.hasPrefix("local.claude-profiles.")
    }

    @objc private func appActivated(_ note: Notification) {
        updateTitle()
    }

    @objc private func appLaunched(_ note: Notification) {
        guard isClaude(note) else { return }
        updateTitle()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard isClaude(note) else { return }
        updateTitle()
        updateIdleProfiles()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.updateIdleProfiles() }
    }

    private func updateTitle() {
        guard let button = item.button else { return }
        let registry = Registry.load()
        let front = registry.profile(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        if let front { lastActiveSlug = front.slug }
        let shown = front ?? lastActiveSlug.flatMap { registry.find($0) }

        button.image = shown?.badge(size: 16, alpha: front == nil ? 0.45 : 1)
            ?? Palette.badge("C", color: .systemGray, size: 16, alpha: 0.45)
        button.toolTip = front.map { "You are in \($0.name)" } ?? "Claude Profiles"
    }

    private func bindHotKeys() {
        let slugs = Registry.load().profiles.map(\.slug)
        hotKeys.bindDigits(slugs.map { slug in { [weak self] in self?.open(slug: slug) } })
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        bindHotKeys()
        let registry = Registry.load()
        let front = registry.profile(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)

        if registry.profiles.isEmpty { menu.addItem(disabled("No profiles yet")) }
        for (index, profile) in registry.profiles.enumerated() {
            menu.addItem(profileItem(profile, index: index, isFront: profile.slug == front?.slug))
        }

        let pending = Updater.pending(in: registry)
        if !pending.isEmpty || !failures.isEmpty { menu.addItem(.separator()) }
        if !pending.isEmpty {
            let title = "Update All Profiles to Claude \(ProfileApps.claudeVersion ?? "")"
            menu.addItem(action(title, #selector(updateAll)))
        }
        for (slug, message) in failures.sorted(by: { $0.key < $1.key }) {
            let entry = action("Update failed: \(registry.find(slug)?.name ?? slug)…", #selector(showFailure(_:)))
            entry.representedObject = message
            menu.addItem(entry)
        }

        let running = registry.profiles.filter { $0.runningApp != nil }
        if !running.isEmpty {
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")
            quit.submenu = NSMenu()
            for profile in running {
                let entry = action(profile.name, #selector(quitProfile(_:)))
                entry.representedObject = profile.slug
                entry.image = profile.badge()
                quit.submenu?.addItem(entry)
            }
            menu.addItem(quit)
        }

        menu.addItem(.separator())
        menu.addItem(action("Add Profile…", #selector(addProfile)))
        menu.addItem(action("Show Profile Apps in Finder", #selector(showFolder)))
        let login = action("Start at Login", #selector(toggleLoginItem))
        login.state = Installer.isLoginItemInstalled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Profiles", #selector(quitSelf), key: "q"))
    }

    private func profileItem(_ profile: Profile, index: Int, isFront: Bool) -> NSMenuItem {
        let title = building.contains(profile.slug) ? "\(profile.name) (updating…)" : profile.name
        let entry = action(title, #selector(openProfile(_:)), key: index < HotKeys.digitKeyCodes.count ? "\(index + 1)" : "")
        entry.keyEquivalentModifierMask = [.control, .option]
        entry.representedObject = profile.slug
        entry.image = profile.badge()
        entry.state = profile.runningApp != nil ? .on : .off
        if isFront {
            entry.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            ])
        }
        return entry
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func open(slug: String) {
        guard let profile = Registry.load().find(slug), !building.contains(slug) else { return }
        let needsBuild = profile.runningApp == nil && ProfileApps.needsBuild(profile)
        guard needsBuild else {
            ProfileApps.open(profile) { [weak self] error in self?.report(error) }
            return
        }
        building.insert(slug)
        buildQueue.async { [weak self] in
            ProfileApps.open(profile) { error in
                DispatchQueue.main.async {
                    self?.building.remove(slug)
                    self?.report(error)
                }
            }
        }
    }

    private func updateIdleProfiles() {
        let idle = Updater.pending().filter { $0.runningApp == nil && !building.contains($0.slug) }
        guard !idle.isEmpty else { return }
        rebuild(idle, restartRunning: false)
    }

    private func rebuild(_ profiles: [Profile], restartRunning: Bool) {
        let slugs = Set(profiles.map(\.slug))
        building.formUnion(slugs)
        buildQueue.async { [weak self] in
            let outcome = Updater.update(profiles, restartRunning: restartRunning)
            DispatchQueue.main.async {
                guard let self else { return }
                self.building.subtract(slugs)
                for profile in outcome.updated { self.failures.removeValue(forKey: profile.slug) }
                for (profile, error) in outcome.failed { self.failures[profile.slug] = error.localizedDescription }
                self.updateTitle()
            }
        }
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String else { return }
        open(slug: slug)
    }

    @objc private func quitProfile(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String, let profile = Registry.load().find(slug) else { return }
        _ = ProfileApps.quit(profile)
    }

    @objc private func updateAll() {
        let pending = Updater.pending().filter { !building.contains($0.slug) }
        let running = pending.filter { $0.runningApp != nil }
        if !running.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Update running profiles?"
            alert.informativeText = "\(running.map(\.appName).joined(separator: ", ")) will quit, update to Claude "
                + "\(ProfileApps.claudeVersion ?? "") and reopen. Unsent messages and running Claude Code sessions in them will stop."
            alert.addButton(withTitle: "Update and Reopen")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        rebuild(pending, restartRunning: true)
    }

    @objc private func showFailure(_ sender: NSMenuItem) {
        report(ProfileError(sender.representedObject as? String ?? "Unknown error."))
    }

    @objc private func addProfile() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add Claude Profile"
        alert.informativeText = "Creates a separate Claude app with its own login, chats and settings."
        alert.addButton(withTitle: "Add and Open")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(frame: NSRect(x: 0, y: 28, width: 260, height: 24))
        nameField.placeholderString = "Profile name, for example Work"
        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24), pullsDown: false)
        let used = Set(Registry.load().profiles.map(\.color))
        for name in Palette.names {
            colorPopup.addItem(withTitle: name.capitalized)
            colorPopup.lastItem?.image = Palette.badge(" ", color: Palette.color(named: name), size: 12)
            colorPopup.lastItem?.representedObject = name
        }
        if let free = Palette.names.firstIndex(where: { !used.contains($0) }) { colorPopup.selectItem(at: free) }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 52))
        container.addSubview(nameField)
        container.addSubview(colorPopup)
        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            var registry = Registry.load()
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            let profile = try registry.add(name: name, color: colorPopup.selectedItem?.representedObject as? String)
            bindHotKeys()
            open(slug: profile.slug)
        } catch {
            report(error)
        }
    }

    @objc private func showFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.profileApps])
    }

    @objc private func toggleLoginItem() {
        if Installer.isLoginItemInstalled {
            Installer.uninstallLoginItem()
        } else {
            do { try Installer.installLoginItem() } catch { report(error) }
        }
    }

    @objc private func quitSelf() {
        NSApp.terminate(nil)
    }

    private func report(_ error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }
}
