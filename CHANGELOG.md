# Changelog

All notable changes to Tibber Menu Bar. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.2.0] - 2026-10-09

### Added
- Automatic updates through Sparkle, with "Check for Updates…" in Settings → General.
- Energy and tax breakdown of the current (or selected) price: hover the price tile.
- Solar: homes that feed power into the grid see the net power, the export, and today's production.
- Colorblind-friendly level colors (Settings → Prices → Level colors).
- `--check-updates` diagnostic that queries the update feed without showing any UI.

### Changed
- Clock times follow the macOS locale (12-hour where that is the convention).
- CI renders the popover screenshots in several languages and attaches them to each run.

## [0.1.0] - 2026-10-09

First public release.

- Current Tibber price in the menu bar: cents, currency or plain; optional trend arrow, level word, next slot's price and live power.
- Popover dashboard: price now, live power from Tibber Pulse, today's usage and cost, low and high, cheapest window, price chart for today and tomorrow.
- Notifications: tomorrow's prices, a cheap window about to start, price thresholds.
- Ten languages: English, Dutch, German, Norwegian, Swedish, Danish, Finnish, French, Spanish, Italian.
- macOS 14 or later.

[Unreleased]: https://github.com/robinnewstory/tibber-menu-bar/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/robinnewstory/tibber-menu-bar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/robinnewstory/tibber-menu-bar/releases/tag/v0.1.0
