import AppKit
import SwiftUI
import TibberCore

/// Renders the popover (or the menu bar preview) to a PNG with demo data, for the README and the website.
///   "Tibber Menu Bar" --snapshot out.png [--dark] [--menubar] [-AppleLanguages "(nl)"]
/// The PNG is written inside the app's sandbox container (path printed); copy it from there.
/// True while rendering a screenshot. Views swap AppKit-backed controls (menus, segmented pickers, bordered
/// buttons), which ImageRenderer cannot draw, for plain SwiftUI stand-ins.
private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var isSnapshot: Bool { get { self[SnapshotKey.self] } set { self[SnapshotKey.self] = newValue } }
}

enum Snapshot {
    @MainActor static func run(arguments args: [String]) {
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else {
            print("usage: --snapshot <file.png> [--dark] [--menubar]"); exit(2)
        }
        // The app is sandboxed, so the file lands in the container's temporary folder; the path is printed.
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(URL(fileURLWithPath: args[i + 1]).lastPathComponent)
        let dark = args.contains("--dark")
        // Settings come from the argument domain, so the demo never reads or writes this user's preferences.
        let defaults = UserDefaults.standard
        var volatile = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        for (key, value) in [PriceOptions.key: try? JSONEncoder().encode(PriceOptions()),
                             MenuBarOptions.key: try? JSONEncoder().encode(MenuBarOptions()),
                             PopoverOptions.key: try? JSONEncoder().encode(PopoverOptions()),
                             "notificationPrefs": try? JSONEncoder().encode(NotificationPrefs(cheapWindowStart: true))] {
            volatile[key] = value
        }
        defaults.setVolatileDomain(volatile, forName: UserDefaults.argumentDomain)

        _ = NSApplication.shared
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSApp.appearance = appearance
        let model = PriceModel.shared
        model.loadDemo()

        let content: AnyView = args.contains("--menubar")
            ? AnyView(MenuBarPreview(model: model).padding(8).background(Color(nsColor: .windowBackgroundColor)))
            : AnyView(PopoverView(model: model))
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, dark ? .dark : .light).environment(\.isSnapshot, true))
        renderer.scale = 2
        var png: Data?
        appearance.performAsCurrentDrawingAppearance {
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                png = rep.representation(using: .png, properties: [:])
            }
        }
        guard let png else { print("could not render"); exit(1) }
        do { try png.write(to: out); print("wrote \(out.path)") } catch { print("write failed: \(error)"); exit(1) }
    }
}
