# Changelog

All notable changes to Tibber Menu Bar. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.3.0] - 2026-10-09

Fixes for the eight issues reported by @thijsvandberg. Thanks!

### Fixed
- The cheap-window notification came again every slot while the window ran; it now comes once per window (#3).
- Live power never started when the app launched before the network was up, such as at login; the homes query is now retried until it succeeds and the stream starts as soon as the websocket URL is known (#4).
- Every live websocket failure scheduled two reconnects and left the old socket open; failures are now attributed to the socket they came from and reconnects are single and cancellable (#5).
- A live connection that stayed open but went silent was never replaced; a 60-second watchdog now reconnects it (#6).
- Changing the home or resolution during a fetch was ignored; the forced refresh now runs as soon as the fetch finishes (#7).
- Disconnect left the home name, prices, consumption and cost on disk; it now removes the cache, the last live reading and the notification state, and results of a fetch that was still running are dropped (#10).

### Changed
- The home id is passed to Tibber as a GraphQL variable instead of being spliced into the query text (#8).
- The token is only sent to a secure websocket on a tibber.com host; the Settings footer, README and website now say "only ever sent to Tibber" (#9).

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

[Unreleased]: https://github.com/robinnewstory/tibber-menu-bar/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/robinnewstory/tibber-menu-bar/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/robinnewstory/tibber-menu-bar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/robinnewstory/tibber-menu-bar/releases/tag/v0.1.0
