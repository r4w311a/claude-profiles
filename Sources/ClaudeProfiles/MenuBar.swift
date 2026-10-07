import AppKit

/// Menu bar switcher: a colored dot for the frontmost Claude profile, plus a menu to open, focus, or quit profiles.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var lastActiveSlug: String?

    override init() {
        super.init()
        menu.delegate = self
        item.menu = menu

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }
        updateTitle()
    }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = MenuBarController()
        withExtendedLifetime(controller) { app.run() }
        exit(0)
    }

    // MARK: - Status item

    @objc private func workspaceChanged(_ note: Notification) {
        updateTitle()
    }

    private func frontmostProfile(_ registry: Registry) -> Profile? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == Paths.claudeBundleID else { return nil }
        let instance = Instance(app: front, dataDir: Instances.userDataDir(of: front.processIdentifier))
        return Instances.profile(for: instance, in: registry)
    }

    private func updateTitle() {
        guard let button = item.button else { return }
        let registry = Registry.load()
        let front = frontmostProfile(registry)
        if let front { lastActiveSlug = front.slug }

        button.image = Palette.dot(front?.nsColor ?? .tertiaryLabelColor, size: 9)
        button.imagePosition = front == nil ? .imageOnly : .imageLeading
        button.title = front.map { " \($0.name)" } ?? ""
        button.toolTip = front.map { "Claude: \($0.name)" } ?? "Claude Profiles"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let registry = Registry.load()
        let instances = Instances.running()
        let front = frontmostProfile(registry)

        if registry.profiles.isEmpty {
            menu.addItem(disabled("No profiles yet"))
        }
        for profile in registry.profiles {
            let running = Instances.instance(for: profile, in: instances) != nil
            let isFront = profile.slug == front?.slug
            let isLast = profile.slug == lastActiveSlug && front == nil
            let entry = NSMenuItem(title: profile.name, action: #selector(openProfile(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = profile.slug
            entry.image = Palette.dot(profile.nsColor)
            entry.state = running ? .on : .off
            if isFront || isLast {
                entry.attributedTitle = NSAttributedString(string: profile.name, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                ])
            }
            entry.toolTip = running ? "Running – click to focus" : "Click to launch"
            menu.addItem(entry)
        }

        let runningProfiles = registry.profiles.filter { Instances.instance(for: $0, in: instances) != nil }
        if !runningProfiles.isEmpty {
            let quit = NSMenuItem(title: "Quit Profile", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for profile in runningProfiles {
                let entry = NSMenuItem(title: profile.name, action: #selector(quitProfile(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = profile.slug
                entry.image = Palette.dot(profile.nsColor)
                sub.addItem(entry)
            }
            quit.submenu = sub
            menu.addItem(.separator())
            menu.addItem(quit)
        }

        if !registry.profiles.isEmpty {
            let signIn = NSMenuItem(title: "Sign In to Profile", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for profile in registry.profiles {
                let entry = NSMenuItem(title: "\(profile.name)…", action: #selector(signInProfile(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = profile.slug
                entry.image = Palette.dot(profile.nsColor)
                sub.addItem(entry)
            }
            signIn.submenu = sub
            if runningProfiles.isEmpty { menu.addItem(.separator()) }
            menu.addItem(signIn)
        }

        menu.addItem(.separator())
        menu.addItem(action("Add Profile…", #selector(addProfile)))
        menu.addItem(action("Show Profiles Folder", #selector(showFolder)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Claude Profiles", #selector(quitSelf), key: "q"))
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

    private func profile(from sender: NSMenuItem) -> Profile? {
        (sender.representedObject as? String).flatMap { Registry.load().find($0) }
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let profile = profile(from: sender) else { return }
        do { try Instances.open(profile) } catch { showError(error) }
    }

    @objc private func quitProfile(_ sender: NSMenuItem) {
        guard let profile = profile(from: sender) else { return }
        _ = Instances.quit(profile)
    }

    /// Quits other instances so the claude:// sign-in callback can only reach this profile, then reopens them.
    @objc private func signInProfile(_ sender: NSMenuItem) {
        guard let profile = profile(from: sender) else { return }
        signIn(profile)
    }

    private func signIn(_ profile: Profile) {
        let registry = Registry.load()
        let others = Instances.others(than: profile)
        NSApp.activate(ignoringOtherApps: true)

        if !others.isEmpty {
            let names = others.map { Instances.profile(for: $0, in: registry)?.name ?? "pid \($0.pid)" }
            let confirm = NSAlert()
            confirm.messageText = "Sign in to \(profile.name)"
            confirm.informativeText = "Google sign-in comes back through a claude:// link that macOS may hand to the wrong Claude window. "
                + "These will quit until you're signed in, then reopen: \(names.joined(separator: ", ")).\n\n"
                + "Running Claude Code sessions in them will stop."
            confirm.addButton(withTitle: "Quit Others & Continue")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }

            let stuck = Instances.quitAndWait(others)
            if !stuck.isEmpty {
                Instances.relaunch(others.filter { o in !stuck.contains { $0.pid == o.pid } })
                let stuckNames = stuck.map { Instances.profile(for: $0, in: registry)?.name ?? "pid \($0.pid)" }
                showError(ProfileError("\(stuckNames.joined(separator: ", ")) didn't quit (maybe it's showing a confirmation). Quit it and try again."))
                return
            }
        }

        do { try Instances.open(profile) } catch { showError(error); Instances.relaunch(others); return }

        let done = NSAlert()
        done.messageText = "Sign in to \(profile.name) now"
        done.informativeText = "Finish signing in inside the Claude \(profile.name) window, then click Done"
            + (others.isEmpty ? "." : " to reopen the other profiles.")
        done.addButton(withTitle: "Done")
        done.runModal()
        Instances.relaunch(others)
    }

    @objc private func addProfile() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add Claude Profile"
        alert.informativeText = "Creates a separate data folder and a launcher in ~/Applications/Claude Profiles. Sign in to the account the first time it opens."
        alert.addButton(withTitle: "Add & Launch")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        stack.orientation = .vertical
        stack.alignment = .leading
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        nameField.placeholderString = "Profile name, e.g. Work"
        let colorPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 24), pullsDown: false)
        let used = Set(Registry.load().profiles.map(\.color))
        for name in Palette.names {
            colorPopup.addItem(withTitle: name.capitalized)
            colorPopup.lastItem?.image = Palette.dot(Palette.color(named: name))
            colorPopup.lastItem?.representedObject = name
        }
        if let free = Palette.names.firstIndex(where: { !used.contains($0) }) { colorPopup.selectItem(at: free) }
        stack.addArrangedSubview(nameField)
        stack.addArrangedSubview(colorPopup)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        do {
            var registry = Registry.load()
            let profile = try registry.add(name: name, color: colorPopup.selectedItem?.representedObject as? String)
            try Bundles.writeLauncher(for: profile)
            signIn(profile)
        } catch {
            showError(error)
        }
    }

    @objc private func showFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.launchers])
    }

    @objc private func quitSelf() {
        NSApp.terminate(nil)
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
