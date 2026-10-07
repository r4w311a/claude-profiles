#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build -c release
.build/release/claude-profiles install

if [ "$1" = "--login" ]; then
  "$HOME/.local/bin/claude-profiles" install-agent
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "Note: add ~/.local/bin to your PATH to use \`claude-profiles\` directly." ;;
esac
echo "Done. Open ~/Applications/Claude Profiles.app to start the menu bar switcher."
