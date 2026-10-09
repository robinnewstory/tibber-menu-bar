import AppKit
import SwiftUI

// "Tibber Menu Bar" --status prints the cached state (never the token) for diagnostics.
if CommandLine.arguments.contains("--status") {
    Diagnostics.printStatus()
    exit(0)
}
if CommandLine.arguments.contains("--check-token") {
    Diagnostics.checkToken()
    exit(0)
}
TibberMenuBarApp.main()
