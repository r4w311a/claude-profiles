# claude-profiles

Run several Claude Desktop accounts side by side on one Mac (for example a personal subscription and a company Team plan) without logging out and back in. It's a local, do-it-yourself take on multiclaude.app.

Each profile is a separate Claude Desktop process started with its own data folder (`--user-data-dir`), so each keeps its own login, chats, settings and MCP config. The official `/Applications/Claude.app` is never modified, so auto-update keeps working.

## Install

```sh
./install.sh            # or: ./install.sh --login   (start the menu bar app at login)
```

This installs:
- `~/.local/bin/claude-profiles`: the CLI.
- `~/Applications/Claude Profiles.app`: the menu bar switcher.
- `~/Applications/Claude Profiles/Claude <Name>.app`: one launcher per profile. Find them with Spotlight ("Claude Work") or pin them to the Dock. A launcher brings that profile's window to the front if it's running, and launches it if not.

## Set up your accounts

```sh
claude-profiles adopt-default Personal --color blue   # the account Claude is signed into today
claude-profiles add Work --color orange               # a fresh, empty profile
claude-profiles open Work                             # sign in to the other account here
```

`adopt-default` registers Claude's existing folder (`~/Library/Application Support/Claude`), so your current login and history stay as they are. New profiles live in `~/Library/Application Support/Claude-Profiles/<name>/`.

You can also add profiles from the menu bar app (**Add Profile…**).

## Commands

| Command | What it does |
| --- | --- |
| `list` | Profiles, colors, and which are running (pid) |
| `add <name> [--color c]` | New profile + launcher |
| `adopt-default <name> [--color c]` | Register the existing default Claude folder |
| `open <name>` | Focus if running, otherwise launch |
| `quit <name>` | Quit just that profile |
| `signin <name> [--yes]` | Quit other instances while you sign in to this one, then reopen them |
| `remove <name> [--trash-data]` | Remove the profile and launcher; `--trash-data` moves its folder to the Trash (never the default folder) |
| `install` | Copy the binary to `~/.local/bin` and rebuild the apps (run after code changes) |
| `menubar` | Run the menu bar switcher in the foreground |
| `install-agent` / `uninstall-agent` | Start the menu bar app at login (LaunchAgent) |

Colors: blue, orange, green, purple, red, pink, teal, yellow, indigo, mint, brown, gray.

## Menu bar

The status item shows the frontmost profile's color dot and name, and a grey dot when Claude isn't in front. The menu lists every profile: a ✓ means it's running, bold means it's frontmost or was last used, and clicking a profile focuses or launches it. There's also **Quit Profile ▸**, **Sign In to Profile ▸**, **Add Profile…** and **Show Profiles Folder**.

## Caveats

- **Same Dock icon:** every instance is the same signed Claude.app, so the Dock and Cmd-Tab show identical icons. Use the menu bar dot to tell them apart. Changing the icon would mean re-signing Claude, which breaks auto-update and Keychain access.
- **Use the launchers, not the plain Claude icon:** while any profile is running, clicking the stock Claude icon just focuses whichever instance macOS picks. Pin the `Claude <Name>` launchers to the Dock instead.
- **First sign-in:** use `claude-profiles signin <name>` or the menu bar's **Sign In to Profile ▸**. Google sign-in finishes in your browser and comes back through a `claude://` link. macOS gives that link to one Claude instance (usually the oldest), and only the instance that started the login accepts it. So `signin` quits the other instances, opens the profile, waits while you sign in, then reopens them. This is needed only once per profile; the login persists after that.
- **Shared Claude Code settings:** `~/.claude` (CLI settings and memory) is shared by every profile's Code tab. Each tab still authenticates with its own desktop login.
- **Shared logs:** all instances write to `~/Library/Logs/Claude`.
- **Updates may break it:** this relies on Chromium's `--user-data-dir` flag. Claude already ignores its own `CLAUDE_USER_DATA_DIR` override in signed builds, so a future update could block the flag too. After a big update, open a profile and check that `claude-profiles list` shows it running with its own folder.
- **Company policy:** check whether your company allows its account on a machine that also has a personal one.

## Uninstall

```sh
claude-profiles uninstall-agent
rm -r ~/.local/bin/claude-profiles ~/Applications/Claude\ Profiles.app ~/Applications/Claude\ Profiles
```

Profile data stays in `~/Library/Application Support/Claude-Profiles/` until you remove it yourself.
