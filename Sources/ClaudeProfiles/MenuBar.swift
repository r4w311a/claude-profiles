import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showWindow: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var subscriptions: Set<AnyCancellable> = []

    init(model: AppModel, showWindow: @escaping () -> Void) {
        self.model = model
        self.showWindow = showWindow
        super.init()
        menu.delegate = self
        item.menu = menu

        model.$frontSlug
            .combineLatest(model.$activeSlug, model.$profiles)
            .receive(on: RunLoop.main)
            .sink { [weak self] front, active, profiles in self?.updateTitle(front: front, active: active, profiles: profiles) }
            .store(in: &subscriptions)
    }

    private func updateTitle(front: String?, active: String?, profiles: [Profile]) {
        guard let button = item.button else { return }
        let shown = profiles.first { $0.slug == (front ?? active) }
        button.image = shown?.badge(size: 16, alpha: front == nil ? 0.45 : 1)
            ?? Palette.badge("C", color: .systemGray, size: 16, alpha: 0.45)
        button.toolTip = shown.map { front == nil ? "Last used: \($0.name)" : "You are in \($0.name)" } ?? "Claude Profiles"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if model.profiles.isEmpty { menu.addItem(disabled("No profiles yet")) }

        for (index, profile) in model.profiles.enumerated() {
            let building = model.buildingSlugs.contains(profile.slug)
            let title = building ? "\(profile.name) (updating…)" : profile.name
            let entry = action(title, #selector(openProfile(_:)),
                               key: index < HotKeys.digitKeyCodes.count ? "\(index + 1)" : "")
            entry.keyEquivalentModifierMask = [.control, .option]
            entry.representedObject = profile.slug
            entry.image = profile.badge()
            entry.state = model.runningSlugs.contains(profile.slug) ? .on : .off
            if profile.slug == model.frontSlug {
                entry.attributedTitle = NSAttributedString(string: title, attributes: [
                    .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                ])
            }
            menu.addItem(entry)
        }
        if model.profiles.count > 1 {
            let previous = action("Previous Profile", #selector(previousProfile), key: "`")
            previous.keyEquivalentModifierMask = [.control, .option]
            menu.addItem(previous)
        }

        menu.addItem(.separator())
        if model.isUpdating {
            menu.addItem(disabled("Updating profiles…"))
        } else if !model.pendingSlugs.isEmpty {
            menu.addItem(action("Update All Profiles to Claude \(model.claudeVersion ?? "")", #selector(updateAll)))
        }

        let running = model.profiles.filter { model.runningSlugs.contains($0.slug) }
        if !running.isEmpty {
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

        menu.addItem(action("Manage Profiles…", #selector(manage), key: ","))
        menu.addItem(action("Add Profile…", #selector(addProfile)))
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

    @objc private func openProfile(_ sender: NSMenuItem) {
        if let slug = sender.representedObject as? String { model.switchTo(slug) }
    }

    @objc private func previousProfile() {
        model.switchToPrevious()
    }

    @objc private func quitProfile(_ sender: NSMenuItem) {
        if let slug = sender.representedObject as? String { model.quit(slug) }
    }

    @objc private func updateAll() {
        model.updateAll()
    }

    @objc private func manage() {
        showWindow()
    }

    @objc private func addProfile() {
        showWindow()
        model.isAddingProfile = true
    }

    @objc private func quitSelf() {
        NSApp.terminate(nil)
    }
}
