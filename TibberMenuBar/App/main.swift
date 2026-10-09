import AppKit
import SwiftUI

// Diagnostics (never print the token):
//   "Tibber Menu Bar" --status        cached prices, current slot, last live reading
//   "Tibber Menu Bar" --check-token   verify the stored token against the API
//   "Tibber Menu Bar" --fetch         fetch prices now and update the cache
if CommandLine.arguments.contains("--status") { Diagnostics.printStatus(); exit(0) }
if CommandLine.arguments.contains("--check-token") { Diagnostics.checkToken(); exit(0) }
if CommandLine.arguments.contains("--fetch") { Diagnostics.fetch(); exit(0) }
TibberMenuBarApp.main()
