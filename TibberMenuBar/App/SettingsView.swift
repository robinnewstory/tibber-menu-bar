import SwiftUI
import TibberCore

struct SettingsView: View {
    @ObservedObject var model: PriceModel
    @ObservedObject private var updater = Updater.shared
    @State private var tokenInput = ""
    @State private var connecting = false
    @State private var accountMessage: String?

    var body: some View {
        Form {
            accountSection
            pricesSection
            menuBarSection
            popoverSection
            notificationsSection
            generalSection
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { if model.hasToken && model.homes.isEmpty { Task { await model.loadHomes() } } }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            SecureField("Personal access token", text: $tokenInput, prompt: Text("Paste your token"))
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(connecting ? "Connecting…" : (model.hasToken ? "Replace token" : "Connect")) {
                    connecting = true
                    Task {
                        let problem = await model.saveToken(tokenInput)
                        accountMessage = problem ?? String(localized: "Connected.")
                        if problem == nil { tokenInput = "" }
                        connecting = false
                    }
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                if model.hasToken {
                    Button("Disconnect") { model.clearToken(); accountMessage = String(localized: "Token removed.") }
                }
                Spacer()
                Link("Create a token…", destination: URL(string: "https://developer.tibber.com/settings/access-token")!)
            }
            if let accountMessage {
                Text(accountMessage).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Tibber account")
        } footer: {
            Text(model.hasToken
                 ? "Your token is stored in the macOS Keychain and only ever sent to Tibber."
                 : "Create a personal access token on developer.tibber.com under Settings → Access Token, then paste it here.")
        }
    }

    // MARK: Prices

    private var pricesSection: some View {
        Section {
            Picker("Home", selection: Binding(get: { model.prices.homeId ?? "" }, set: { model.prices.homeId = $0.isEmpty ? nil : $0 })) {
                ForEach(model.homes) { home in
                    Text(homeLabel(home)).tag(home.id)
                }
            }
            .disabled(model.homes.count <= 1)
            Picker("Resolution", selection: $model.prices.resolution) {
                ForEach(Resolution.allCases, id: \.self) { Text($0.localizedLabel).tag($0) }
            }
            Picker("Cheap and expensive mean", selection: $model.prices.levelSource) {
                Text("Tibber's level, compared with recent days").tag(LevelSource.tibber)
                Text("Below or above today's average").tag(LevelSource.average)
            }
            Picker("Level colors", selection: $model.prices.palette) {
                ForEach(PriceOptions.Palette.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Prices")
        } footer: {
            Text("The price level colors the icon and the tiles, provides the level word, and colors the chart.")
        }
    }

    private func homeLabel(_ home: HomeInfo) -> String {
        var parts = [home.displayName]
        if !home.hasSubscription { parts.append(String(localized: "no subscription")) }
        if home.liveMeasurements { parts.append(String(localized: "Pulse")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Menu bar

    private var menuBarSection: some View {
        Section {
            Picker("Price format", selection: $model.menuBar.format) {
                ForEach(LabelStyle.allCases, id: \.self) { Text($0.localizedLabel).tag($0) }
            }
            Picker("Icon", selection: $model.menuBar.icon) {
                ForEach(MenuBarOptions.Icon.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Toggle("Trend arrow", isOn: $model.menuBar.trendArrow)
            Toggle("Next slot's price", isOn: $model.menuBar.nextPrice)
            Toggle("Level word", isOn: $model.menuBar.levelWord)
            Toggle("Live power", isOn: $model.menuBar.livePower)
                .disabled(!model.liveEnabled)
            LabeledContent("Preview") {
                MenuBarPreview(model: model)
            }
        } header: {
            Text("Menu bar")
        } footer: {
            if !model.liveEnabled { Text("Live power in the menu bar needs the Pulse stream, enabled under Popover.") }
        }
    }

    // MARK: Popover

    private var popoverSection: some View {
        Section {
            Toggle("Live power from Tibber Pulse", isOn: $model.popover.livePower)
                .disabled(!model.liveSupported)
            Picker("Cheapest window", selection: $model.notifications.plannerHours) {
                ForEach(Planner.durationsHours, id: \.self) { Text("\($0) hours").tag($0) }
            }
            Picker("Chart style", selection: $model.popover.chart.style) {
                ForEach(ChartOptions.Style.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Chart colors", selection: $model.popover.chart.colorMode) {
                ForEach(ChartOptions.ColorMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Chart height", selection: $model.popover.chart.height) {
                ForEach(ChartOptions.Height.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Chart opens on", selection: $model.popover.chart.defaultDay) {
                ForEach(ChartOptions.DefaultDay.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Toggle("Average line", isOn: $model.popover.chart.showAverage)
            Toggle("Shade the cheapest window", isOn: $model.popover.chart.shadeWindow)
            Toggle("Dim past slots", isOn: $model.popover.chart.dimPast)
            Toggle("Price axis starts at zero", isOn: $model.popover.chart.fromZero)
        } header: {
            Text("Popover")
        } footer: {
            Text(model.liveSupported
                 ? "The cheapest window length is also used by the window notification and the chart shading."
                 : "Live power needs a home with a Tibber Pulse. The cheapest window length is also used by the window notification and the chart shading.")
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("Cheapest window is about to start", isOn: $model.notifications.cheapWindowStart)
            Toggle("Tomorrow's prices are published", isOn: $model.notifications.tomorrowPublished)
            ThresholdRow(title: "Price drops below", unit: centUnit, value: $model.notifications.belowCents, defaultValue: 15)
            ThresholdRow(title: "Price rises above", unit: centUnit, value: $model.notifications.aboveCents, defaultValue: 35)
        } header: {
            Text("Notifications")
        } footer: {
            Text("The window reminder comes 10 minutes ahead. Thresholds watch the current slot and fire once per crossing. macOS asks for permission the first time you enable one.")
        }
    }

    private var centUnit: String {
        PriceFormatter.centSymbol(for: model.data?.currency ?? "EUR").trimmingCharacters(in: .whitespaces) + "/kWh"
    }

    // MARK: General

    private var generalSection: some View {
        Section {
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticallyChecksForUpdates }, set: { updater.automaticallyChecksForUpdates = $0 }))
            LabeledContent("Version") {
                HStack {
                    Text(verbatim: Self.versionText)
                    Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates).controlSize(.small)
                }
            }
            if let error = model.lastError {
                LabeledContent("Last problem") {
                    Text(error).foregroundStyle(.orange).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("General")
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// A toggle with a cents field that is only editable while the toggle is on.
struct ThresholdRow: View {
    let title: LocalizedStringKey
    let unit: String
    @Binding var value: Double?
    let defaultValue: Double
    @State private var text = ""

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { value != nil },
                set: { on in
                    value = on ? (Double(text.replacingOccurrences(of: ",", with: ".")) ?? defaultValue) : nil
                    if on { text = Self.format(value ?? defaultValue) }
                }
            ))
            TextField("Threshold", text: $text)
                .labelsHidden()
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .disabled(value == nil)
                .onSubmit { commit() }
                .onChange(of: text) { _, _ in commit() }
            Text(verbatim: unit).foregroundStyle(.secondary)
        }
        .onAppear { text = value.map(Self.format) ?? Self.format(defaultValue) }
    }

    private func commit() {
        guard value != nil, let number = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
        value = number
    }

    private static func format(_ v: Double) -> String { String(format: "%g", v) }
}

/// A mock of the menu bar item, so format changes can be judged without looking up.
struct MenuBarPreview: View {
    @ObservedObject var model: PriceModel

    var body: some View {
        HStack(spacing: 5) {
            switch model.menuBar.icon {
            case .bolt: Image(systemName: model.menuSymbol)
            case .dot: Image(nsImage: model.menuDot)
            case .none: EmptyView()
            }
            Text(model.menuTitle).monospacedDigit()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}
