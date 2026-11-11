#!/bin/sh
set -e
cd "$(dirname "$0")/.."

version="$1"
repo="r4w311a/claude-profiles"
tap="r4w311a/homebrew-tap"

if [ -z "$version" ]; then
  echo "usage: scripts/release.sh <version>"
  exit 1
fi
if ! grep -q "current = \"$version\"" Sources/ClaudeProfiles/Version.swift; then
  echo "Set Version.current to $version in Sources/ClaudeProfiles/Version.swift first."
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit your changes before releasing."
  exit 1
fi

for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch"
done

name="claude-profiles-$version"
dist=".build/dist"
rm -rf "$dist"
mkdir -p "$dist/$name"
for tool in claude-profiles claude-profile-launcher; do
  lipo -create ".build/arm64/release/$tool" ".build/x86_64/release/$tool" -output "$dist/$name/$tool"
  codesign --force --sign - "$dist/$name/$tool"
done
cp README.md LICENSE "$dist/$name/"
tar -czf "$dist/$name.tar.gz" -C "$dist" "$name"
sha=$(shasum -a 256 "$dist/$name.tar.gz" | cut -d " " -f 1)

git tag "v$version"
git push origin "v$version"
gh release create "v$version" "$dist/$name.tar.gz" --repo "$repo" --title "v$version" \
  --notes "Install with \`brew install r4w311a/tap/claude-profiles\`, then run \`claude-profiles install\`."

if ! gh repo view "$tap" >/dev/null 2>&1; then
  gh repo create "$tap" --public --description "Homebrew formulae by r4w311a"
fi
rm -rf "$dist/tap"
gh repo clone "$tap" "$dist/tap" -- --quiet
mkdir -p "$dist/tap/Formula"
cat > "$dist/tap/Formula/claude-profiles.rb" <<EOF
class ClaudeProfiles < Formula
  desc "Run several Claude Desktop accounts side by side on a Mac"
  homepage "https://github.com/$repo"
  url "https://github.com/$repo/releases/download/v$version/$name.tar.gz"
  sha256 "$sha"
  license "MIT"

  depends_on macos: :ventura

  def install
    bin.install "claude-profiles"
    libexec.install "claude-profile-launcher"
  end

  def caveats
    <<~EOS
      Finish the setup with:
        claude-profiles install

      Run it again after each upgrade to refresh the menu bar app.
    EOS
  end

  test do
    assert_equal "$version", shell_output("#{bin}/claude-profiles --version").strip
  end
end
EOF
git -C "$dist/tap" add Formula/claude-profiles.rb
git -C "$dist/tap" commit -m "claude-profiles $version"
git -C "$dist/tap" push origin HEAD

echo "Released v$version ($sha)"
