import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case mimoLive = "mimoLive"
    case web = "Web Dashboard"
    case about = "About"

    var id: Self { self }

    var icon: String {
        switch self {
        case .mimoLive: return "video.circle"
        case .web:      return "globe"
        case .about:    return "info.circle"
        }
    }
}

struct SettingsView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updaterService: UpdaterService
    @State private var selection: SettingsPage? = .mimoLive
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var showPasswordMismatch = false
    @State private var showSaved = false
    @State private var portString: String = ""
    @State private var showPortError = false
    @State private var showPortSaved = false

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.rawValue, systemImage: page.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            switch selection ?? .mimoLive {
            case .mimoLive: mimoLiveDetail
            case .web:      webDetail
            case .about:    aboutDetail
            }
        }
        .frame(width: 620, height: 460)
        .onAppear { portString = String(appState.webServerPort) }
    }

    private func applyPort() {
        guard let port = UInt16(portString), port >= 1024 else {
            showPortError = true
            return
        }
        showPortError = false
        appState.changePort(to: port)
        showPortSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showPortSaved = false }
    }

    // MARK: - mimoLive

    private var mimoLiveDetail: some View {
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
    }

    // MARK: - Web Dashboard

    private var webDetail: some View {
        Form {
            Section {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $portString)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyPort() }
                    Button("Apply") { applyPort() }
                        .disabled(portString == String(appState.webServerPort))
                }
                if showPortError {
                    Text("Enter a valid port number (1024\u{2013}65535)")
                        .foregroundColor(.red).font(.caption)
                }
                if showPortSaved {
                    Label("Port changed \u{2014} server restarted", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.caption)
                }
                LabeledContent("URL") {
                    Link("http://localhost:\(String(appState.webServerPort))",
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
                            Text("Passwords don't match")
                                .foregroundColor(.red).font(.caption)
                        }
                        if showSaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green).font(.caption)
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
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutDetail: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("mlController")
                    .font(.title.bold())
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .foregroundColor(.secondary)
            }

            Divider()
                .frame(width: 200)

            VStack(spacing: 10) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updaterService.automaticallyChecksForUpdates },
                    set: { updaterService.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates\u{2026}") {
                    updaterService.checkForUpdates()
                }
                .disabled(!updaterService.canCheckForUpdates)
            }
            .frame(width: 250)

            Divider()
                .frame(width: 200)

            Grid(alignment: .leading, verticalSpacing: 6) {
                GridRow {
                    Text("Installations found")
                        .foregroundColor(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(String(appState.availableMimoLiveApps.count))
                        .font(.body.monospaced())
                }
                GridRow {
                    Text("Active version")
                        .foregroundColor(.secondary)
                    Text(appState.selectedMimoLiveURL?.deletingPathExtension().lastPathComponent ?? "System Default")
                        .font(.body.monospaced())
                }
                GridRow {
                    Text("Web server port")
                        .foregroundColor(.secondary)
                    Text(String(appState.webServerPort))
                        .font(.body.monospaced())
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
