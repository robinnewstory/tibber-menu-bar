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
        // "No update" also ends with an abort; it was already reported above.
        if !done { print("check failed: \(error.localizedDescription)") }
        done = true
    }
}

/// `--install-update`: downloads, verifies and installs whatever the feed offers, with no dialogs, then lets
/// Sparkle relaunch the app. Quit the running app first. For proving a release's update path end to end.
final class HeadlessUpdateDriver: NSObject, SPUUserDriver {
    private var finished = false
    private var expected: UInt64 = 0
    private var received: UInt64 = 0

    static func run() {
        let driver = HeadlessUpdateDriver()
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
        do { try updater.start() } catch { print("updater failed to start: \(error.localizedDescription)"); exit(1) }
        print("installed: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))")
        updater.checkForUpdates()
        let deadline = Date().addingTimeInterval(300)
        while !driver.finished, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        if !driver.finished { print("gave up after 5 minutes") }
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { print("checking…") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("found \(appcastItem.displayVersionString) (\(appcastItem.versionString)); installing")
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("no update: \(error.localizedDescription)"); finished = true; acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        print("error: \(error.localizedDescription)"); finished = true; acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { print("downloading…") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        if expected > 0, received >= expected { print("downloaded \(received) bytes") }
    }
    func showDownloadDidStartExtractingUpdate() { print("extracting and verifying signature…") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("verified; installing and relaunching"); reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        // The installer waits for this process to go away; a command-line run has no event loop to quit politely.
        if !applicationTerminated { print("installer running; exiting so it can swap the app"); exit(0) }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        print("installed, relaunched: \(relaunched)"); finished = true; acknowledgement()
    }
    func dismissUpdateInstallation() { finished = true }
}
