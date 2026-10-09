#!/bin/zsh
# Builds a signed release on this Mac and publishes it: git tag, GitHub release with the zipped app,
# and the Homebrew cask in ../homebrew-tap if that checkout exists.
# Usage: TibberMenuBar/release.sh 0.2.0 ["release notes"]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
VERSION="${1:?usage: release.sh <version> [notes]}"
NOTES="${2:-Tibber Menu Bar $VERSION}"
TAG="v$VERSION"
ASSET="Tibber-Menu-Bar.zip"
OUT="$ROOT/.tools/release"

SPARKLE="$ROOT/.tools/sparkle/bin"
cd "$ROOT"
[[ -x "$SPARKLE/sign_update" ]] || { echo "Sparkle tools missing: extract Sparkle-<version>.tar.xz from github.com/sparkle-project/Sparkle/releases into $ROOT/.tools/sparkle/" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not logged in: run gh auth login" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then echo "Tag $TAG already exists." >&2; exit 1; fi

echo "Tests…"
(cd TibberMenuBar/Packages/TibberCore && swift test 2>&1 | grep -E "Executed .* tests" | tail -1 | grep -q "with 0 failures") \
  || { echo "Tests failed." >&2; exit 1; }

# Record the version in the spec so the repository shows what shipped.
sed -i '' "s/^    MARKETING_VERSION: \".*\"/    MARKETING_VERSION: \"$VERSION\"/" TibberMenuBar/project.yml

echo "Building $VERSION…"
MARKETING_VERSION="$VERSION" "$HERE/build.sh" --no-install
APP="$ROOT/.tools/DerivedData/Build/Products/Release/Tibber Menu Bar.app"
codesign --verify --deep --strict "$APP"
BUILT="$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)"
[[ "$BUILT" == "$VERSION" ]] || { echo "Built version $BUILT does not match $VERSION" >&2; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ASSET"
SHA="$(shasum -a 256 "$OUT/$ASSET" | cut -d' ' -f1)"

# Sparkle: EdDSA signature from the key in the login Keychain, then the appcast entry (served from docs/ by Pages).
SIGNATURE_LINE="$("$SPARKLE/sign_update" "$OUT/$ASSET")"
ED_SIGNATURE="$(print -r -- "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(print -r -- "$SIGNATURE_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[[ -n "$ED_SIGNATURE" && -n "$LENGTH" ]] || { echo "sign_update gave no signature: $SIGNATURE_LINE" >&2; exit 1; }
BUILD="$(defaults read "$APP/Contents/Info" CFBundleVersion)"
print -r -- "$NOTES" > "$OUT/notes.md"
node "$HERE/Scripts/appcast.js" "$ROOT/docs/appcast.xml" "$VERSION" "$BUILD" \
  "https://github.com/robinnewstory/tibber-menu-bar/releases/download/$TAG/$ASSET" "$LENGTH" "$ED_SIGNATURE" "$OUT/notes.md"

git add TibberMenuBar/project.yml docs/appcast.xml
git diff --cached --quiet || git commit -q -m "Release $TAG"
git tag -a "$TAG" -m "Tibber Menu Bar $VERSION"
git push -q origin HEAD "$TAG"
gh release create "$TAG" "$OUT/$ASSET#Tibber Menu Bar $VERSION (macOS 14 or later)" --title "Tibber Menu Bar $VERSION" --notes "$NOTES"
# A push that carries a tag does not always start a Pages build, and the appcast must go live for Sparkle to see the update.
gh api -X POST repos/robinnewstory/tibber-menu-bar/pages/builds > /dev/null 2>&1 || echo "Could not request a Pages build; check the appcast at https://robinnewstory.github.io/tibber-menu-bar/appcast.xml" >&2
echo "Released $TAG — sha256 $SHA"

TAP="$ROOT/../homebrew-tap"
if [[ -f "$TAP/Casks/tibber-menu-bar.rb" ]]; then
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$TAP/Casks/tibber-menu-bar.rb"
  (cd "$TAP" && git add Casks && git commit -q -m "tibber-menu-bar $VERSION" && git push -q)
  echo "Homebrew cask updated."
else
  echo "No tap checkout at $TAP — update Casks/tibber-menu-bar.rb by hand: version $VERSION, sha256 $SHA"
fi
