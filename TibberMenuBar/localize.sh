#!/bin/zsh
# Regenerates App/Resources/Localizable.xcstrings: lets xcodebuild extract every localizable string from the
# app sources, then fills in the translations from Localization/translations-*.js. Fails if a string lacks a
# translation, so add new strings to the tables first.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
XCODEGEN="$(find "$ROOT/.tools" -type f -name xcodegen -perm -u+x 2>/dev/null | head -1 || true)"
[[ -n "$XCODEGEN" ]] || { echo "xcodegen not found under $ROOT/.tools" >&2; exit 1; }
cd "$HERE"
"$XCODEGEN" generate --spec project.yml --quiet
# Start from an empty catalog so the export only contains keys found in the sources, not leftovers.
CATALOG="App/Resources/Localizable.xcstrings"
printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' > "$CATALOG"
EXPORT="$ROOT/.tools/localization-export"
rm -rf "$EXPORT" && mkdir -p "$EXPORT"
xcodebuild -exportLocalizations -project TibberMenuBar.xcodeproj -localizationPath "$EXPORT" > "$EXPORT/export.log" 2>&1 || { tail -20 "$EXPORT/export.log" >&2; exit 1; }
node Localization/make-catalog.js "$EXPORT/en.xcloc/Localized Contents/en.xliff" "$CATALOG" Localization/translations-*.js
