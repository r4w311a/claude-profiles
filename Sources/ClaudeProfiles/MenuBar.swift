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
            try Instances.launch(profile)
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
