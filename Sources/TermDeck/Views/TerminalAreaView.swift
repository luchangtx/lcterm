import SwiftUI
import AppKit

struct TerminalAreaView: View {
    @ObservedObject var sessionManager: SessionManager
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue

    private var isDark: Bool {
        AppearanceCenter.resolveIsDark(AppearanceMode(rawValue: appearanceRaw) ?? .system)
    }

    var body: some View {
        ZStack {
            // 终端内容四周留白，颜色与终端背景一致，视觉上成为终端的内边距
            Color(nsColor: TerminalPalette.background(dark: isDark))

            if sessionManager.sessions.isEmpty {
                emptyState
            } else {
                ForEach(sessionManager.sessions) { session in
                    let active = session.id == sessionManager.selectedID
                    TerminalHostView(
                        session: session,
                        onClose: { sessionManager.close(session) }
                    )
                    .padding(.top, 6)
                    .padding(.horizontal, 10)
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(active)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onChange(of: sessionManager.selectedID) { _ in
            focusSelected()
        }
        .onReceive(sessionManager.$sessions) { sessions in
            if sessionManager.selectedID == nil, let first = sessions.first {
                sessionManager.selectedID = first.id
            }
        }
    }

    private func focusSelected() {
        if let session = sessionManager.selectedSession {
            DispatchQueue.main.async {
                sessionManager.focus(session)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary)
            Text("TermDeck 终端")
                .font(.title3.weight(.medium))
            Text("通过左下角 + 新建本地终端或连接远程主机")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TerminalHostView: View {
    @ObservedObject var session: TerminalSession
    var onClose: () -> Void

    var body: some View {
        TerminalNSViewRepresentable(view: session.view)
            .overlay {
                if let ssh = session.sshSession {
                    SSHOverlayView(ssh: ssh, onClose: onClose)
                }
            }
    }
}

struct TerminalNSViewRepresentable: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SSHOverlayView: View {
    @ObservedObject var ssh: SSHSession
    var onClose: () -> Void

    var body: some View {
        switch ssh.state {
        case .connected, .idle:
            EmptyView()
        case .connecting:
            backdrop {
                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在连接 \(ssh.host.host):\(String(ssh.host.port)) …")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        case .failed(let message):
            backdrop {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.yellow)
                    Text("连接失败")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    if ssh.lastConnectError is HostKeyChangedError {
                        Button("我已确认服务器变更，重新信任并连接") {
                            ssh.retrustAndReconnect()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("重试") { ssh.retry() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("关闭", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        case .closed:
            backdrop {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text("连接已断开")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Button("重新连接") { ssh.retry() }
                            .buttonStyle(.borderedProminent)
                        Button("关闭", action: onClose)
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func backdrop<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.88)
            content()
        }
    }
}
