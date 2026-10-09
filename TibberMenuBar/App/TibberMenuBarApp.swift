import SwiftUI
import TibberCore

struct TibberMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = PriceModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            switch model.iconStyle {
            case .bolt:
                Label { Text(model.menuTitle) } icon: { Image(systemName: model.menuSymbol) }
                    .labelStyle(.titleAndIcon)
            case .dot:
                Label { Text(model.menuTitle) } icon: { Image(nsImage: model.menuDot) }
                    .labelStyle(.titleAndIcon)
            case .none:
                Text(model.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PriceModel.shared.start()
    }
}
