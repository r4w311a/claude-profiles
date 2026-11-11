# Claude Profiles

Use more than one Claude account at the same time on a Mac, without logging out and back in.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/window-dark.png">
  <img src="docs/window-light.png" alt="The Claude Profiles window with Personal, Work and Client profiles" width="640">
</picture>

I have a personal Claude subscription and a work Team plan on the same laptop, and switching between them all day got old. This is the small tool I made for myself. It's a personal project, so feel free to use it, change it, or take it in a different direction.

## What you get

- Each account becomes its own app, like **Claude Work**, with its own login, chats and settings
- Every profile has its own color, so the Dock and Cmd-Tab always show which one is which
- Jump between profiles with ⌃⌥1, ⌃⌥2, ⌃⌥3, and go back to the previous one with ⌃⌥`
- A colored letter in the menu bar shows which profile you're in
- Profiles stay up to date when Claude updates

## Install

You need macOS 13 or later, [Claude Desktop](https://claude.ai/download) in your Applications folder, and [Homebrew](https://brew.sh).

```sh
brew install r4w311a/tap/claude-profiles
claude-profiles install
```

The Claude Profiles window opens, and a small icon appears in your menu bar.

## Get started

1. Click **Add Profile**, type a name for the account you already use in Claude (for example "Personal"), keep **This is the account already signed in to Claude** checked, and click **Add Profile**.
2. Click **Add Profile** again for your other account, for example "Work". A new **Claude Work** app opens.
3. Sign in to your other account in that app. When macOS asks to use "Claude Safe Storage", choose **Always Allow**.

That's it. Add as many profiles as you like.

## Everyday use

| To | Do this |
| --- | --- |
| Switch to a profile | ⌃⌥1, ⌃⌥2, ⌃⌥3 and so on |
| Go back to the previous profile | ⌃⌥` |
| Move between profiles | Cmd-Tab, like any other app |
| Move between windows of one profile | Cmd-` |
| Open the Claude Profiles window | Open "Claude Profiles" from Spotlight, or click the menu bar icon and choose **Manage Profiles** |

Turn on **Start at login** and **Open profiles at login** in the window to keep your profiles ready in the background, so even the first switch of the day is instant.

## Updates

Claude updates itself as usual, and Claude Profiles updates your profiles right after. If a profile is open at the time, click **Update All** in the window or the menu bar.

To update Claude Profiles itself:

```sh
brew upgrade claude-profiles
claude-profiles install
```

## Good to know

- Your first account stays in the regular Claude app. The others are copies of it that live in `~/Applications/Claude Profiles` and take almost no disk space.
- The copies are signed on your Mac instead of by Anthropic, so after each Claude update macOS asks once more about "Claude Safe Storage". Choose **Always Allow** again.
- Links that open Claude, and files you open with Claude, go to the regular Claude app.
- Passkey and Microsoft sign-in may not work in the extra profiles. Google sign-in works.
- Claude Code settings in `~/.claude` are shared between profiles.
- If one account belongs to your employer, check that your company is fine with it.
- This is an unofficial tool and isn't affiliated with Anthropic.

## Command line

Everything in the window also works from the terminal.

```
claude-profiles list                          show profiles and what's running
claude-profiles add <name> [--color c]        create a profile
claude-profiles adopt-default <name>          name the account in the regular Claude app
claude-profiles open <name>                   open or switch to a profile
claude-profiles quit <name>                   quit one profile
claude-profiles update [--restart]            update profiles for the installed Claude
claude-profiles remove <name> [--trash-data]  remove a profile
```

## Uninstall

```sh
claude-profiles uninstall
brew uninstall claude-profiles
```

This removes the apps and the menu bar icon. Your profile logins and chats stay in `~/Library/Application Support/Claude-Profiles` until you delete that folder.

## Build from source

You need Swift, which comes with Xcode or `xcode-select --install`.

```sh
git clone https://github.com/r4w311a/claude-profiles.git
cd claude-profiles
./install.sh
```

## License

MIT
