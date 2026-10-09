import AppKit
import Combine
import Sparkle

/// Sparkle, wrapped for SwiftUI. The feed URL and public key live in Info.plist (see project.yml);
/// updates are signed by release.sh and listed in docs/appcast.xml.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &cancellables)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    /// A menu bar app has no window to bring forward, so activate first or Sparkle's panel opens behind everything.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }
}

/// `--check-updates`: asks the feed without showing any UI and prints the answer. For verifying a release.
final class UpdateCheckReporter: NSObject, SPUUpdaterDelegate {
    private var done = false

    static func run() {
        let reporter = UpdateCheckReporter()
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: reporter, userDriverDelegate: nil)
        print("feed: \(controller.updater.feedURL?.absoluteString ?? "none")")
        print("installed: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))")
        controller.updater.checkForUpdateInformation()
        let deadline = Date().addingTimeInterval(30)
        while !reporter.done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        if !reporter.done { print("no answer within 30 s") }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print("update available: \(item.displayVersionString) (\(item.versionString)) at \(item.fileURL?.absoluteString ?? "no enclosure")")
        done = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        print("no update: \(error.localizedDescription)")
        done = true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        print("check failed: \(error.localizedDescription)")
        done = true
    }
}
