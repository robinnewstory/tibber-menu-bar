#!/bin/zsh
# Renders the README/website screenshots from demo data into docs/.
# The installed app is sandboxed and can only write inside its container, so this makes an ad-hoc signed,
# unsandboxed copy under .tools/ and runs that copy's --snapshot mode.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
SRC="${1:-/Applications/Tibber Menu Bar.app}"
COPY="$ROOT/.tools/Snapshot.app"
DOCS="$ROOT/docs"
mkdir -p "$(dirname "$COPY")" && rm -rf "$COPY" && ditto "$SRC" "$COPY"
codesign --force --deep --sign - "$COPY" 2>/dev/null
BIN="$COPY/Contents/MacOS/Tibber Menu Bar"
mkdir -p "$DOCS"
render() {  # render <file> [args…]
  local name="$1"; shift
  local written
  written="$("$BIN" --snapshot "$name" "$@" 2>/dev/null | sed -n 's/^wrote //p')"
  [[ -n "$written" ]] || { echo "render failed: $name" >&2; exit 1; }
  cp "$written" "$DOCS/$name" && echo "docs/$name"
}
render popover-light.png
render popover-dark.png --dark
render menubar-light.png --menubar
render menubar-dark.png --menubar --dark
render popover-nl.png -AppleLanguages "(nl)"
render popover-fr-dark.png --dark -AppleLanguages "(fr)"
