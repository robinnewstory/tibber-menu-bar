# Tibber Menu Bar

A macOS menu bar app that shows your current Tibber electricity price. Click it for a small graph of today's (and, after the day-ahead auction, tomorrow's) prices with the current slot highlighted, low/average/high, and the cheapest two-hour window.

## Setup

1. Create a personal access token at <https://developer.tibber.com/settings/access-token>.
2. Build and install: `TibberMenuBar/build.sh` (needs Xcode, an Apple ID team in `TibberMenuBar/Config/Local.xcconfig`, and XcodeGen under `.tools/` or the ring-widget project's tools folder).
3. Click the bolt in the menu bar → Settings → paste the token → Connect. Pick a home if you have several.

## How it works

- **API**: Tibber's GraphQL API at `api.tibber.com/v1-beta/gql` with a bearer token. The app asks for `priceInfo(resolution: QUARTER_HOURLY)` (96 slots per day; hourly is selectable) for the chosen home. Authentication failures arrive as HTTP 200 with an `UNAUTHENTICATED` GraphQL error, which the client maps to "invalid token".
- **Refreshing**: prices are published once a day, so the app fetches at launch, when the day rolls over, and from 13:00 local time every 15 minutes until tomorrow's prices appear. In between, the menu bar label advances through the cached slots without network traffic. A timer ticks every 30 seconds; wake from sleep triggers a check.
- **Storage**: the token lives in the login Keychain; the last prices are cached in the app's container so the label is populated instantly after launch.
- **Menu bar label**: cents by default (`28.3¢`), or currency / plain in Settings. The bolt icon reflects Tibber's price level.

## Layout

| Path | What |
|---|---|
| `TibberMenuBar/Packages/TibberCore` | API client, models, price math, refresh policy, formatting, token store and cache, with tests (`swift test`). |
| `TibberMenuBar/App` | SwiftUI `MenuBarExtra` app: popover with a Swift Charts graph, settings window, diagnostics (`"Tibber Menu Bar" --status`). |
| `TibberMenuBar/project.yml` | XcodeGen spec (sandboxed, network client entitlement, LSUIElement). |
| `TibberMenuBar/build.sh` | Generates the project, builds Release with a fresh build number, installs to `/Applications`. |
