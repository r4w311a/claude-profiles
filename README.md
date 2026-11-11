# claude-profiles

Use more than one Claude Desktop account at the same time on a Mac, without logging out and back in.

I have a personal Claude subscription and a work Team plan on the same laptop, and switching between them all day got old. This is the small tool I made for myself. It's a personal project, so feel free to use it, change it, or take it in a different direction.

## What it does

- Turns each extra account into its own Mac app, like "Claude Work", with its own login, chats and settings
- Colors each profile app and adds its letter, so the Dock and Cmd-Tab show which is which
- Shows a colored letter in the menu bar for the profile you're in
- Switches profiles instantly with ⌃⌥1, ⌃⌥2 and so on, and ⌃⌥` takes you back to the previous one
- Comes with a small window to add, open, recolor and remove profiles
- Rebuilds the profile apps when Claude updates, with an **Update All** button for the ones that are open

Your current Claude stays exactly as it is and keeps updating itself. Every other profile is a local copy of it with its own name, icon and data folder. The copies take almost no disk space.

## Requirements

- macOS 13 or later
- Claude Desktop in `/Applications`

## Install

With [Homebrew](https://brew.sh):

```sh
brew install r4w311a/tap/claude-profiles
claude-profiles install
```

Run `claude-profiles install` again after `brew upgrade` to refresh the menu bar app.

From source, with Swift from Xcode or `xcode-select --install`:

```sh
git clone https://github.com/r4w311a/claude-profiles.git
cd claude-profiles
./install.sh
```

The source install puts the command in `~/.local/bin`, so make sure that is on your `PATH`. Add `--login` to start the menu bar app when you log in.

## Set up

```sh
claude-profiles adopt-default Personal
claude-profiles add Work
```

`adopt-default` names the account you're already signed in to. `add` creates the app **Claude Work** in `~/Applications/Claude Profiles`. Open it from Spotlight, the Dock or the menu bar and sign in.

You can do the same from the **Claude Profiles** window. It opens after install, and again whenever you open Claude Profiles from Spotlight or choose **Manage Profiles** in the menu bar.

The first time a profile app opens, macOS asks whether it may use "Claude Safe Storage". Choose **Always Allow**. That key protects the profile's login on disk.

## Updates

Claude updates itself as usual. When it does, Claude Profiles rebuilds every profile app that isn't open. For the ones that are open, click **Update All** in the window or the menu bar, or run:

```sh
claude-profiles update --restart
```

## Commands

```
list                          show profiles, what's running, and update state
add <name> [--color c]        create a profile app
adopt-default <name>          name the account in the original Claude app
open <name>                   open or switch to a profile
quit <name>                   quit one profile
update [<name>] [--restart]   rebuild profile apps for the installed Claude
remove <name> [--trash-data]  remove a profile
install-agent                 start the menu bar app at login
```

## Faster switching

- Turn on **Start at login** and **Open profiles at login** to keep every profile running in the background, so even the first switch is instant.
- Cmd-` cycles the windows of the profile you're in, and Cmd-Tab moves between profiles like any other app.

## Good to know

- Profile apps are signed on your Mac instead of by Anthropic. After each Claude update, macOS asks once more for the keychain, and for permissions like screen recording if a profile uses them.
- To skip those repeat prompts, create a code signing certificate named "Claude Profiles" in Keychain Access (Certificate Assistant, Create a Certificate, type Code Signing). The tool uses it automatically.
- Links like `claude://` and files you open with Claude go to the original app.
- Passkey and Microsoft sign-in rely on keychain sharing that only Anthropic's signature allows, so they may not work in profile apps.
- Claude Code settings in `~/.claude` are shared between profiles.
- If one account is from your employer, check that your company is fine with it.
- This is an unofficial tool and isn't affiliated with Anthropic.

## Uninstall

```sh
claude-profiles uninstall-agent
rm -r ~/.local/bin/claude-profiles ~/Applications/Claude\ Profiles.app ~/Applications/Claude\ Profiles
```

Profile data stays in `~/Library/Application Support/Claude-Profiles` until you delete it.

## License

MIT
