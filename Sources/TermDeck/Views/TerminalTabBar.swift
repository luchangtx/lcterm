import SwiftUI

struct TerminalTabBar: View {
    @ObservedObject var sessionManager: SessionManager
    var hosts: [HostConfig]
    var onNewLocal: () -> Void
    var onConnectHost: (HostConfig) -> Void
    var onQuickConnect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sessionManager.sessions) { session in
                        TabItemView(
                            session: session,
                            isSelected: session.id == sessionManager.selectedID,
                            onSelect: { sessionManager.select($0) },
                            onClose: { sessionManager.close($0) }
                        )
                    }
                }
                .padding(.horizontal, 10)
            }

            Menu {
                Button(action: onNewLocal) {
                    Label("新建本地终端", systemImage: "terminal")
                }
                if !hosts.isEmpty {
                    Divider()
                    Text("连接主机")
                    ForEach(hosts) { host in
                        Button { onConnectHost(host) } label: {
                            Label(host.displayTitle, systemImage: "server.rack")
                        }
                    }
                    Divider()
                }
                Button(action: onQuickConnect) {
                    Label("新建主机连接…", systemImage: "plus.circle")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("新建终端或连接")

            Spacer(minLength: 10)
        }
        .padding(.vertical, 5)
        .background(.bar)
    }
}

private struct TabItemView: View {
    @ObservedObject var session: TerminalSession
    var isSelected: Bool
    var onSelect: (TerminalSession) -> Void
    var onClose: (TerminalSession) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.symbol)
                .font(.system(size: 10))
                .foregroundColor(isSelected ? .accentColor : .secondary)
            Text(session.title)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(maxWidth: 150)
                .help(session.title)
            if let ssh = session.sshSession {
                SSHStateDot(ssh: ssh)
            }
            Button {
                onClose(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : Color.primary.opacity(0.045)
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(session) }
    }
}

private struct SSHStateDot: View {
    @ObservedObject var ssh: SSHSession

    var body: some View {
        Group {
            switch ssh.state {
            case .connected:
                EmptyView()
            case .connecting:
                ProgressView().scaleEffect(0.45)
            default:
                Circle()
                    .fill(ssh.state.isError ? Color.red : Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

extension ConnectionState {
    var isError: Bool {
        if case .failed = self { return true }
        return false
    }
}
