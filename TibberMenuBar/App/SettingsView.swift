import SwiftUI
import TibberCore

struct SettingsView: View {
    @ObservedObject var model: PriceModel
    @State private var tokenInput = ""
    @State private var saving = false
    @State private var message: String?
    @State private var belowText = ""
    @State private var aboveText = ""

    var body: some View {
        Form {
            Section("Tibber account") {
                SecureField("Personal access token", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(saving ? "Connecting…" : (model.hasToken ? "Replace token" : "Connect")) {
                        saving = true
                        Task {
                            let ok = await model.saveToken(tokenInput)
                            message = ok ? "Connected." : (model.lastError ?? "Failed")
                            if ok { tokenInput = "" }
                            saving = false
                        }
                    }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                    if model.hasToken {
                        Button("Disconnect") { model.clearToken(); message = "Token removed." }
                    }
                    Button("Get a token…") { NSWorkspace.shared.open(URL(string: "https://developer.tibber.com/settings/access-token")!) }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Text(model.hasToken ? "A token is stored in your Keychain." : "No token yet. Create one at developer.tibber.com → Settings → Access Token.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Prices") {
                Picker("Home", selection: Binding(get: { model.selectedHomeId ?? "" }, set: { model.selectedHomeId = $0.isEmpty ? nil : $0 })) {
                    ForEach(model.homes) { home in
                        Text(home.displayName + (home.hasSubscription ? "" : " (no subscription)") + (home.liveMeasurements ? " · Pulse" : "")).tag(home.id)
                    }
                }
                .disabled(model.homes.count <= 1)
                Picker("Resolution", selection: $model.resolution) {
                    ForEach(Resolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section("Menu bar") {
                Picker("Price format", selection: $model.labelStyle) {
                    ForEach(LabelStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Bolt icon", isOn: $model.showIcon)
                Toggle("Trend arrow (next slot up/down)", isOn: $model.showTrend)
                Toggle("Live power from Tibber Pulse (in the popover)", isOn: $model.showLivePower)
                    .disabled(!model.liveSupported)
                Toggle("Also show live power in the menu bar", isOn: $model.liveInMenuBar)
                    .disabled(!model.liveSupported || !model.showLivePower)
                if !model.liveSupported { Text("Live power needs a home with a Tibber Pulse.").font(.caption).foregroundStyle(.secondary) }
            }

            Section("Notifications") {
                Toggle("Cheap window about to start", isOn: Binding(get: { model.notificationPrefs.cheapWindowStart }, set: { model.notificationPrefs.cheapWindowStart = $0 }))
                Picker("Window length", selection: Binding(get: { model.notificationPrefs.plannerHours }, set: { model.notificationPrefs.plannerHours = $0 })) {
                    ForEach(Planner.durationsHours, id: \.self) { Text("\($0) h").tag($0) }
                }
                Toggle("Tomorrow's prices published", isOn: Binding(get: { model.notificationPrefs.tomorrowPublished }, set: { model.notificationPrefs.tomorrowPublished = $0 }))
                HStack {
                    Toggle("Price drops below", isOn: Binding(get: { model.notificationPrefs.belowCents != nil }, set: { on in
                        model.notificationPrefs.belowCents = on ? (Double(belowText.replacingOccurrences(of: ",", with: ".")) ?? 15) : nil
                        if on, belowText.isEmpty { belowText = "15" }
                    }))
                    TextField("¢", text: $belowText).frame(width: 60).textFieldStyle(.roundedBorder)
                        .onSubmit { if model.notificationPrefs.belowCents != nil { model.notificationPrefs.belowCents = Double(belowText.replacingOccurrences(of: ",", with: ".")) } }
                    Text("¢/kWh").foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("Price rises above", isOn: Binding(get: { model.notificationPrefs.aboveCents != nil }, set: { on in
                        model.notificationPrefs.aboveCents = on ? (Double(aboveText.replacingOccurrences(of: ",", with: ".")) ?? 35) : nil
                        if on, aboveText.isEmpty { aboveText = "35" }
                    }))
                    TextField("¢", text: $aboveText).frame(width: 60).textFieldStyle(.roundedBorder)
                        .onSubmit { if model.notificationPrefs.aboveCents != nil { model.notificationPrefs.aboveCents = Double(aboveText.replacingOccurrences(of: ",", with: ".")) } }
                    Text("¢/kWh").foregroundStyle(.secondary)
                }
                Text("Thresholds apply to the price of the current slot; you're told once when it crosses. macOS asks for permission the first time a notification is enabled.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                if let error = model.lastError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            if model.hasToken && model.homes.isEmpty { Task { await model.loadHomes() } }
            if let b = model.notificationPrefs.belowCents { belowText = String(format: "%g", b) }
            if let a = model.notificationPrefs.aboveCents { aboveText = String(format: "%g", a) }
        }
    }
}
