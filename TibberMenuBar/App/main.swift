import AppKit
import SwiftUI

// "Tibber Menu Bar" --status prints the cached state (never the token) for diagnostics.
if CommandLine.arguments.contains("--status") {
    Diagnostics.printStatus()
    exit(0)
}
TibberMenuBarApp.main()
