import SwiftUI

struct SettingsView: View {

    @EnvironmentObject var appState: AppState
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPasswordMismatch = false
    @State private var showSaved = false

    var body: some View {
        TabView {
            mimoLiveTab
                .tabItem { Label("mimoLive", systemImage: "video.circle") }

            webTab
                .tabItem { Label("Web Dashboard", systemImage: "globe") }

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }

    // MARK: - mimoLive Tab

    private var mimoLiveTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
            } header: {
                Text("Startup")
            } footer: {
                Text("Automatically start mlController when you log in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                if appState.availableMimoLiveApps.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("No mimoLive installations found in /Applications or ~/Downloads.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    // nil = system default (whichever NSWorkspace resolves first)
                    Picker("Version to launch", selection: $appState.selectedMimoLiveURL) {
                        Text("System Default")
                            .tag(Optional<URL>.none)
                        ForEach(appState.availableMimoLiveApps) { app in
                            Text(app.displayName)
                                .tag(Optional(app.url))
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if let selected = appState.selectedMimoLiveURL {
                        Text(selected.path)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Installation")
            } footer: {
                Text("Select which version to launch when pressing Start. \"System Default\" uses whichever version macOS considers primary.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Bundle ID") { Text("com.boinx.mimoLive").font(.caption.monospaced()) }
                LabeledContent("HTTP API")  { Text("http://localhost:8989/api/v1").font(.caption.monospaced()) }
                LabeledContent("Documents") { Text(".tvshow files in ~/Documents").font(.caption.monospaced()) }
            } header: {
                Text("Integration Details")
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    // MARK: - Web Tab

    private var webTab: some View {
        Form {
            Section {
                LabeledContent("Port") {
                    Text("\(appState.webServerPort)")
                        .foregroundColor(.secondary)
                }
                LabeledContent("URL") {
                    Link("http://localhost:\(appState.webServerPort)",
                         destination: URL(string: "http://localhost:\(appState.webServerPort)")!)
                }
            } header: {
                Text("Web Server")
            }

            Section {
                Toggle("Enable Password Protection", isOn: $appState.passwordEnabled)

                if appState.passwordEnabled {
                    SecureField("New Password", text: $newPassword)
                    SecureField("Confirm Password", text: $confirmPassword)

                    HStack {
                        Button("Save Password") {
                            if newPassword == confirmPassword && !newPassword.isEmpty {
                                appState.webPassword = newPassword
                                newPassword = ""
                                confirmPassword = ""
                                showPasswordMismatch = false
                                showSaved = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSaved = false }
                            } else {
                                showPasswordMismatch = true
                            }
                        }
                        .disabled(newPassword.isEmpty)

                        if showPasswordMismatch {
                            Text("Passwords don't match").foregroundColor(.red).font(.caption)
                        }
                        if showSaved {
                            Label("Saved", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                        }
                    }

                    if !appState.webPassword.isEmpty {
                        Text("Password is set. Leave fields blank to keep existing password.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Clients must supply the password via HTTP Basic Auth or the X-mlcontroller-password header.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 4) {
                Text("mlController")
                    .font(.title2.bold())
                Text("Version 1.0.0")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Installations found",
                        value: "\(appState.availableMimoLiveApps.count)")
                InfoRow(label: "Active version",
                        value: appState.selectedMimoLiveURL?.deletingPathExtension().lastPathComponent ?? "System Default")
                InfoRow(label: "mlController Port",
                        value: "\(appState.webServerPort)")
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 160, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
        }
    }
}
