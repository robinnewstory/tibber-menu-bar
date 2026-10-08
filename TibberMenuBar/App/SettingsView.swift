import SwiftUI
import TibberCore

struct SettingsView: View {
    @ObservedObject var model: PriceModel
    @State private var tokenInput = ""
    @State private var saving = false
    @State private var message: String?

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
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
                Text(model.hasToken ? "A token is stored in your Keychain." : "No token yet. Create one at developer.tibber.com → Settings → Access Token.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Prices") {
                Picker("Home", selection: Binding(get: { model.selectedHomeId ?? "" }, set: { model.selectedHomeId = $0.isEmpty ? nil : $0 })) {
                    ForEach(model.homes) { home in
                        Text(home.displayName + (home.hasSubscription ? "" : " (no subscription)")).tag(home.id)
                    }
                }
                .disabled(model.homes.count <= 1)
                Picker("Resolution", selection: $model.resolution) {
                    ForEach(Resolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Menu bar format", selection: $model.labelStyle) {
                    ForEach(LabelStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Show bolt icon", isOn: $model.showIcon)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                if let error = model.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { if model.hasToken && model.homes.isEmpty { Task { await model.loadHomes() } } }
    }
}
