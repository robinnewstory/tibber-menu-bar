import AppKit
import SwiftUI
import TibberCore

TibberClient.setAppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")

// Diagnostics (never print the token):
//   "Tibber Menu Bar" --status        cached prices, current slot, last live reading
//   "Tibber Menu Bar" --check-token   verify the stored token against the API
//   "Tibber Menu Bar" --fetch         fetch prices now and update the cache
//   "Tibber Menu Bar" --snapshot f.png render the popover with demo data (--dark, --menubar)
//   "Tibber Menu Bar" --check-updates  ask the Sparkle feed whether a newer version exists
//   "Tibber Menu Bar" --install-update install what the feed offers without any dialogs (quit the app first)
if CommandLine.arguments.contains("--status") { Diagnostics.printStatus(); exit(0) }
if CommandLine.arguments.contains("--check-token") { Diagnostics.checkToken(); exit(0) }
if CommandLine.arguments.contains("--fetch") { Diagnostics.fetch(); exit(0) }
if CommandLine.arguments.contains("--dump") { Diagnostics.dumpToday(); exit(0) }
if CommandLine.arguments.contains("--check-updates") { UpdateCheckReporter.run(); exit(0) }
if CommandLine.arguments.contains("--install-update") { HeadlessUpdateDriver.run(); exit(0) }
if CommandLine.arguments.contains("--snapshot") { MainActor.assumeIsolated { Snapshot.run(arguments: CommandLine.arguments) }; exit(0) }
TibberMenuBarApp.main()
