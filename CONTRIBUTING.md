# Contributing

Thanks for helping out. Bug reports, translation fixes and small, focused pull requests are all welcome.

## Building

See [Build from source](README.md#build-from-source). In short: Xcode 15 or later, XcodeGen under `.tools/`, a `Config/Local.xcconfig` with your Team ID, then `TibberMenuBar/build.sh`. The core package has tests: `swift test --package-path TibberMenuBar/Packages/TibberCore`.

## Translations

The app is translated by the maintainer with help from a language model, not by native speakers, so corrections are the most useful contribution of all. Every language is in `TibberMenuBar/Localization/translations-*.js`, one table per group of languages, keyed by the English source string:

```js
"Cheapest window": { nl: "Goedkoopste venster", de: "Günstigstes Zeitfenster", ... },
```

- Keep placeholders exactly as in the key: `%@` for text, `%lld` for whole numbers. Positional forms such as `%1$@` are fine when the translation reorders them.
- A value may be `{ one: "...", other: "..." }` when a number needs plural forms.
- Strings that stay the same in every language go in the `untranslated` list.
- After editing, run `TibberMenuBar/localize.sh` and commit the regenerated `App/Resources/Localizable.xcstrings` together with the table.

To add a language, add its code as a new column to every key in one of the tables, run `localize.sh`, build, and check the popover with `"Tibber Menu Bar" --snapshot x.png -AppleLanguages "(xx)"`. The generator refuses to build the catalog while any key lacks a value, so it will tell you what is missing.

For a quick fix without a build, open an issue with the "Translation fix" template: the English string, the current translation, and the better one.

## Code changes

- User-facing text goes through SwiftUI's localized initializers or `String(localized:)`, and gets a translation in every language before the build (see above). The build silently falls back to English for strings that are not in the tables, so `localize.sh` is part of the workflow, not an afterthought.
- `TibberCore` stays free of UI and localization: wording for its enums and errors lives in `App/Localized.swift`.
- Screenshots in `docs/` come from `TibberMenuBar/snapshots.sh` and demo data, never from a real account.
- Never commit a token, a Team ID, or anything from `Config/Local.xcconfig`.

## Releases

Releases are built and signed by the maintainer with `TibberMenuBar/release.sh`, which also signs the update for Sparkle and bumps the Homebrew cask. CI only runs tests and an unsigned build.
