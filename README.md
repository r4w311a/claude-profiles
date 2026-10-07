# claude-profiles

Use more than one Claude Desktop account at the same time on a Mac, without logging out and back in.

I have a personal Claude subscription and a work Team plan on the same laptop, and switching between them all day got old. This is the small tool I made for myself. It's a personal project, so feel free to use it, change it, or take it in a different direction.

## What it does

- Runs any number of Claude Desktop accounts side by side, each with its own login and chats
- Creates a launcher app per profile, so you can open them from Spotlight or the Dock
- Shows a colored dot in the menu bar for the profile you're in
- Handles sign-in, so Google login lands in the right window
- Leaves the official Claude app untouched, so updates keep working

Each profile is a separate Claude Desktop process started with its own data folder.

## Requirements

- macOS 13 or later
- Claude Desktop in `/Applications`
- Swift, which comes with Xcode or `xcode-select --install`

## Install

```sh
git clone https://github.com/r4w311a/claude-profiles.git
cd claude-profiles
./install.sh
```

Add `--login` to start the menu bar app when you log in. The command is installed to `~/.local/bin`, so make sure that is on your `PATH`.

## Set up

```sh
claude-profiles adopt-default Personal
claude-profiles add Work
claude-profiles signin Work
```

`adopt-default` keeps the account you're already signed in to. `signin` closes your other Claude windows while you log in to the new one, then reopens them. You only need it once per profile.

After that, open **Claude Work** or **Claude Personal** from Spotlight, or pick a profile from the menu bar.

## Commands

```
list                          show profiles and what's running
add <name> [--color c]        create a profile
adopt-default <name>          use the existing Claude data as a profile
open <name>                   open or focus a profile
quit <name>                   quit one profile
signin <name>                 sign in to a profile safely
remove <name> [--trash-data]  remove a profile
install-agent                 start the menu bar app at login
```

## Good to know

- Every window shows the same Claude icon in the Dock and Cmd-Tab. The menu bar dot tells you which account is in front.
- Open profiles from their launchers. The regular Claude icon focuses whichever window macOS picks.
- Claude Code settings in `~/.claude` are shared between profiles.
- This depends on a Chromium option that Claude doesn't document. A future update could stop it from working.
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
