import SwiftUI
import AppKit

struct MenuBarView: View {

    @EnvironmentObject var appState: AppState
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Status Header ──────────────────────────────────────────
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isMimoLiveRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: appState.isMimoLiveRunning ? .green : .red, radius: 4)

                Text(appState.isMimoLiveRunning ? "mimoLive is Running" : "mimoLive is Stopped")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        isRefreshing = true
                        await appState.refresh()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default,
                                   value: isRefreshing)
                }
                .buttonStyle(.plain)
                .help("Refresh status")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // ── Control Buttons ────────────────────────────────────────
            HStack(spacing: 8) {
                ControlButton(
                    label: "Start",
                    systemImage: "play.fill",
                    color: .green,
                    isDisabled: appState.isMimoLiveRunning
                ) {
                    Task { await appState.startMimoLive() }
                }

                ControlButton(
                    label: "Stop",
                    systemImage: "stop.fill",
                    color: .red,
                    isDisabled: !appState.isMimoLiveRunning
                ) {
                    appState.stopMimoLive()
                }

                ControlButton(
                    label: "Restart",
                    systemImage: "arrow.2.circlepath",
                    color: .orange,
                    isDisabled: !appState.isMimoLiveRunning
                ) {
                    Task { await appState.restartMimoLive() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // ── mimoLive Version Picker (only when multiple installs) ──
            if appState.availableMimoLiveApps.count > 1 {
                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "film.stack")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Version:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { appState.selectedMimoLiveURL },
                        set: { appState.selectedMimoLiveURL = $0 }
                    )) {
                        Text("Default").tag(Optional<URL>(nil))
                        ForEach(appState.availableMimoLiveApps) { app in
                            Text(app.displayName).tag(Optional<URL>(app.url))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }

            Divider()

            // ── Open Documents ─────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !appState.openDocuments.isEmpty {
                        SectionHeader(title: "Open in mimoLive", icon: "play.rectangle.fill")

                        ForEach(appState.openDocuments) { doc in
                            DocumentRow(name: doc.displayName, iconName: "doc.fill", tint: .blue)
                        }
                    }

                    // ── Local Documents ────────────────────────────────
                    if !appState.localDocuments.isEmpty {
                        SectionHeader(title: "Available Documents", icon: "folder.fill")

                        ForEach(appState.localDocuments, id: \.self) { url in
                            let name = url.deletingPathExtension().lastPathComponent
                            let isOpen = appState.openDocuments.contains {
                                !$0.filePath.isEmpty && URL(fileURLWithPath: $0.filePath) == url
                            }
                            let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
                            Button {
                                Task { await appState.openDocument(at: url) }
                            } label: {
                                DocumentRow(
                                    name: name,
                                    iconName: "doc.badge.arrow.up",
                                    tint: isOpen ? .green : .secondary,
                                    badge: isOpen ? "open" : nil,
                                    nsImage: fileIcon
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if appState.openDocuments.isEmpty && appState.localDocuments.isEmpty {
                        HStack {
                            Spacer()
                            Text(appState.isMimoLiveRunning ? "No documents found" : "Start mimoLive to see documents")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 12)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxHeight: 260)

            Divider()

            // ── Footer ─────────────────────────────────────────────────
            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(URL(string: "http://localhost:\(appState.webServerPort)")!)
                } label: {
                    Label("Web Dashboard", systemImage: "globe")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open web dashboard in browser")

                Spacer()

                Button {
                    appState.openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .task {
            // Server already started by AppDelegate; just refresh the UI
            await appState.refresh()
        }
    }
}

// MARK: - Subviews

private struct ControlButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(color)
        .disabled(isDisabled)
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.caption)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .kerning(0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

private struct DocumentRow: View {
    let name: String
    let iconName: String
    let tint: Color
    var badge: String? = nil
    var nsImage: NSImage? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let img = nsImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: iconName)
                    .foregroundColor(tint)
                    .frame(width: 16)
            }

            Text(name)
                .font(.body)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let badge = badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(Color.clear)
        .hoverEffect()
    }
}

// MARK: - Hover Effect Helper

extension View {
    func hoverEffect() -> some View {
        modifier(HoverEffectModifier())
    }
}

struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.2) : Color.clear)
            .cornerRadius(4)
            .onHover { isHovered = $0 }
    }
}
