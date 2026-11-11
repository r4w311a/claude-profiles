import AppKit
import SwiftUI

struct ProfilesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            Divider().opacity(0.5)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.profiles, id: \.slug) { profile in
                        ProfileCard(model: model, profile: profile)
                    }
                    if model.profiles.isEmpty {
                        EmptyStateView(model: model)
                    } else if model.profiles.count > 1 {
                        Text("Tip: \(HotKeys.symbol)` jumps back to the profile you used before.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            Divider().opacity(0.5)
            FooterView(model: model)
        }
        .frame(minWidth: 580, minHeight: 440)
        .background(VisualEffectBackground().ignoresSafeArea())
        .sheet(isPresented: $model.isAddingProfile) { AddProfileSheet(model: model) }
    }
}

private struct HeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Profiles")
                    .font(.system(size: 22, weight: .semibold))
                Text(model.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            UpdateAllButton(model: model)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }
}

private struct UpdateAllButton: View {
    @ObservedObject var model: AppModel

    private var isUpToDate: Bool { model.pendingSlugs.isEmpty }

    var body: some View {
        Button(action: model.updateAll) {
            HStack(spacing: 6) {
                if model.isUpdating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isUpToDate ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                }
                Text(model.isUpdating ? "Updating" : isUpToDate ? "Up to Date" : "Update All")
            }
            .frame(minWidth: 110)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isUpToDate || model.isUpdating)
        .help("Rebuild every profile app for the installed Claude version")
    }
}

private struct ProfileCard: View {
    @ObservedObject var model: AppModel
    let profile: Profile

    private var isHovering: Bool { model.hoveredSlug == profile.slug }
    private var isRunning: Bool { model.runningSlugs.contains(profile.slug) }
    private var isActive: Bool { model.activeSlug == profile.slug }
    private var isBuilding: Bool { model.buildingSlugs.contains(profile.slug) }
    private var color: Color { Color(nsColor: profile.nsColor) }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: model.icon(for: profile))
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(profile.name).font(.system(size: 15, weight: .semibold))
                    if profile.isDefault { Tag(text: "Original", color: .secondary) }
                    if isActive { Tag(text: "Last used", color: color) }
                }
                StatusLine(model: model, profile: profile, isRunning: isRunning, isBuilding: isBuilding)
            }

            Spacer(minLength: 12)

            if let shortcut = model.shortcut(for: profile) {
                Text(shortcut)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            Button(isRunning ? "Switch" : "Open") { model.switchTo(profile.slug) }
                .controlSize(.large)
                .frame(minWidth: 72)
                .disabled(isBuilding)

            ProfileActionsMenu(model: model, profile: profile, isRunning: isRunning)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.075 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isActive ? color.opacity(0.6) : Color.primary.opacity(0.06), lineWidth: isActive ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { model.setHovered(profile.slug, hovering) }
        }
        .onTapGesture(count: 2) { model.switchTo(profile.slug) }
        .contextMenu { ProfileActions(model: model, profile: profile, isRunning: isRunning) }
    }
}

private struct StatusLine: View {
    @ObservedObject var model: AppModel
    let profile: Profile
    let isRunning: Bool
    let isBuilding: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(isRunning ? "Running" : "Not running")
            if isBuilding {
                Text("·")
                ProgressView().controlSize(.mini)
                Text("Updating")
            } else if let failure = model.failures[profile.slug] {
                Text("·")
                Text("Update failed").foregroundStyle(.red).help(failure)
            } else if model.pendingSlugs.contains(profile.slug) {
                Text("·")
                Text(isRunning ? "Update ready, restart to apply" : "Update ready").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

private struct ProfileActionsMenu: View {
    @ObservedObject var model: AppModel
    let profile: Profile
    let isRunning: Bool

    var body: some View {
        Menu {
            ProfileActions(model: model, profile: profile, isRunning: isRunning)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct ProfileActions: View {
    @ObservedObject var model: AppModel
    let profile: Profile
    let isRunning: Bool

    var body: some View {
        if isRunning {
            Button("Quit \(profile.appName)") { model.quit(profile.slug) }
        }
        if !profile.isDefault {
            Button("Rebuild App") { model.rebuild(profile.slug) }
        }
        Menu("Color") {
            ForEach(Palette.names, id: \.self) { name in
                Button((name == profile.color ? "✓ " : "") + name.capitalized) {
                    model.setColor(name, for: profile.slug)
                }
            }
        }
        Button("Show in Finder") { model.reveal(profile.slug) }
        Divider()
        Button("Remove…") { model.confirmRemove(profile.slug) }
    }
}

private struct EmptyStateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.crop.square.stack")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No profiles yet").font(.headline)
            Text("Add one for each Claude account you use.")
                .foregroundStyle(.secondary)
            Button("Add Profile") { model.isAddingProfile = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
}

private struct FooterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Button { model.isAddingProfile = true } label: {
                Label("Add Profile", systemImage: "plus")
            }
            Spacer()
            Toggle("Start at login", isOn: Binding(get: { model.startsAtLogin }, set: model.setStartsAtLogin))
                .fixedSize()
            Toggle("Open profiles at login", isOn: $model.openProfilesAtLogin)
                .fixedSize()
                .disabled(!model.startsAtLogin)
                .help("Start every profile in the background when you log in, so the first switch is instant")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private final class AddProfileForm: ObservableObject {
    @Published var name = ""
    @Published var color: String
    @Published var error: String?

    init(color: String) {
        self.color = color
    }
}

private struct AddProfileSheet: View {
    @ObservedObject var model: AppModel
    @StateObject private var form: AddProfileForm

    init(model: AppModel) {
        self.model = model
        _form = StateObject(wrappedValue: AddProfileForm(color: model.suggestedColor))
    }

    private var trimmedName: String { form.name.trimmingCharacters(in: .whitespaces) }
    private var initial: String { trimmedName.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: Palette.badge(initial, color: Palette.color(named: form.color), size: 46))
                VStack(alignment: .leading, spacing: 3) {
                    Text("New Profile").font(.system(size: 17, weight: .semibold))
                    Text("A separate Claude app with its own login and chats.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Name, for example Work", text: $form.name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit(add)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 12), count: 6), spacing: 12) {
                ForEach(Palette.names, id: \.self) { swatch in
                    Circle()
                        .fill(Color(nsColor: Palette.color(named: swatch)))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: swatch == form.color ? 2 : 0).padding(-4))
                        .contentShape(Circle())
                        .onTapGesture { form.color = swatch }
                        .help(swatch.capitalized)
                }
            }

            if let error = form.error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.isAddingProfile = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add Profile", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        do {
            try model.add(name: trimmedName, color: form.color)
            model.isAddingProfile = false
        } catch {
            form.error = error.localizedDescription
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
