import SwiftUI
import AppKit

struct AppSheet: Identifiable {
    enum Mode {
        case create, edit, credentials
    }

    let id = UUID()
    var config: HostConfig
    var mode: Mode
}

struct ContentView: View {
    @StateObject private var hostStore = HostStore()
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var placeholderBrowser = RemoteFileBrowser()
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("showFilePanel") private var showFilePanel = true
    @State private var sheet: AppSheet?
    @State private var selectedHostID: UUID?

    var body: some View {
        NavigationSplitView {
            HostSidebarView(
                hostStore: hostStore,
                sessionManager: sessionManager,
                selectedHostID: $selectedHostID,
                onConnect: { connect(host: $0) },
                onNewHost: { sheet = AppSheet(config: HostConfig(), mode: .create) },
                onEdit: { sheet = AppSheet(config: $0, mode: .edit) }
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 330)
        } detail: {
            detailColumn
        }
        .sheet(item: $sheet) { item in
            ConnectSheetView(
                mode: item.mode,
                host: item.config,
                hostStore: hostStore,
                sessionManager: sessionManager
            )
        }
        .onAppear {
            AppearanceCenter.apply(AppearanceMode(rawValue: appearanceRaw) ?? .system)
            sessionManager.onSSHConnected = { ssh in
                ssh.fileBrowser.bind(session: ssh)
            }
            sessionManager.onSSHDisconnected = { ssh in
                ssh.fileBrowser.bind(session: nil)
            }
        }
        .onChange(of: appearanceRaw) { raw in
            let mode = AppearanceMode(rawValue: raw) ?? .system
            AppearanceCenter.apply(mode)
            sessionManager.applyThemeToAll(dark: AppearanceCenter.resolveIsDark(mode))
        }
        .onReceive(NotificationCenter.default.publisher(for: .tdNewLocalShell)) { _ in
            sessionManager.newLocalShell()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tdNewHost)) { _ in
            sheet = AppSheet(config: HostConfig(), mode: .create)
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            TerminalTabBar(
                sessionManager: sessionManager,
                hosts: hostStore.hosts,
                onNewLocal: { sessionManager.newLocalShell() },
                onConnectHost: { connect(host: $0) },
                onQuickConnect: { sheet = AppSheet(config: HostConfig(), mode: .create) }
            )
            Divider()

            HSplitView {
                TerminalAreaView(sessionManager: sessionManager)
                    .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if showFilePanel {
                    FileManagerPanelView(browser: activeBrowser)
                        .frame(minWidth: 260, idealWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("外观", selection: $appearanceRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Image(systemName: mode.icon)
                            .tag(mode.rawValue)
                            .help(mode.label)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 96)

                Toggle(isOn: $showFilePanel) {
                    Image(systemName: "sidebar.right")
                }
                .toggleStyle(.button)
                .help("显示/隐藏文件面板")

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("设置（⌘,）")
            }
        }
    }

    private var activeBrowser: RemoteFileBrowser {
        if let ssh = sessionManager.selectedSession?.sshSession, ssh.state == .connected {
            return ssh.fileBrowser
        }
        if let last = sessionManager.aliveSSHs.last {
            return last.fileBrowser
        }
        return placeholderBrowser
    }

    private func connect(host: HostConfig) {
        switch host.authMethod {
        case .password:
            if let password = hostStore.password(host.id), !password.isEmpty {
                sessionManager.openSSH(to: host, password: password, keyPassphrase: "")
            } else {
                sheet = AppSheet(config: host, mode: .credentials)
            }
        case .privateKey:
            sessionManager.openSSH(
                to: host,
                password: "",
                keyPassphrase: hostStore.passphrase(host.id) ?? ""
            )
        }
    }
}
