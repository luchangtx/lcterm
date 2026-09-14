import AppKit
import SwiftTerm
import Combine

/// 一个终端标签页：本地 shell 或 SSH 会话
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    enum Kind {
        case local
        case ssh(SSHSession)
    }

    let id = UUID()
    let kind: Kind
    let view: NSView
    let coordinator: AnyObject
    @Published var title: String
    var cancellables = Set<AnyCancellable>()

    init(kind: Kind, view: NSView, title: String, coordinator: AnyObject) {
        self.kind = kind
        self.view = view
        self.title = title
        self.coordinator = coordinator
    }

    var sshSession: SSHSession? {
        if case .ssh(let session) = kind { return session }
        return nil
    }

    var isLocal: Bool { sshSession == nil }

    var symbol: String { isLocal ? "laptopcomputer" : "server.rack" }

    /// SSH 标题变化（OSC 转义序列）同步到标签页
    func bindTitle(from ssh: SSHSession) {
        ssh.$title
            .receive(on: DispatchQueue.main)
            .assign(to: \.title, on: self)
            .store(in: &cancellables)
    }
}

// MARK: - Delegates

@MainActor
final class SSHShellCoordinator: NSObject, TerminalViewDelegate {
    weak var session: SSHSession?

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        session?.resize(cols: newCols, rows: newRows)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        session?.write(data)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        session?.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor
final class LocalShellCoordinator: NSObject, LocalProcessTerminalViewDelegate {
    var onTitle: (String) -> Void = { _ in }
    var onTerminated: () -> Void = {}

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitle(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTerminated()
    }
}

// MARK: - SessionManager

@MainActor
final class SessionManager: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var selectedID: UUID?
    @Published var activeSSH: SSHSession?

    var onSSHConnected: ((SSHSession) -> Void)?
    var onSSHDisconnected: ((SSHSession) -> Void)?

    var theme: TerminalThemeApplier = { view, dark in
        view.nativeBackgroundColor = TerminalPalette.background(dark: dark)
        view.nativeForegroundColor = TerminalPalette.foreground(dark: dark)
    }

    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selectedID }
    }

    var aliveSSHs: [SSHSession] {
        sessions.compactMap { $0.sshSession }.filter { $0.state == .connected }
    }

    func stateFor(_ host: HostConfig) -> ConnectionState {
        sessions.compactMap { $0.sshSession }
            .first { $0.host.id == host.id }?.state ?? .idle
    }

    // MARK: 本地终端

    func newLocalShell() {
        let view = MenuedLocalTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.hideBuiltInScroller()
        theme(view, AppearanceCenter.isDark)

        let coordinator = LocalShellCoordinator()
        let count = sessions.filter { $0.isLocal }.count + 1
        let session = TerminalSession(
            kind: .local,
            view: view,
            title: "本地终端 \(count)",
            coordinator: coordinator
        )

        coordinator.onTitle = { [weak session] title in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            session?.title = trimmed
        }
        coordinator.onTerminated = { [weak session] in
            session?.title = "已退出"
        }

        // 清屏：先在模拟器层直接清空（含滚动缓冲），再让 shell 重绘提示符
        view.onClearScreen = { [weak view] in
            guard let view else { return }
            view.feed(text: "\u{1B}[3J\u{1B}[2J\u{1B}[H")
            view.process?.send(data: ArraySlice<UInt8>([0x0C]))
        }

        view.processDelegate = coordinator
        view.startProcess(
            executable: "/bin/zsh",
            args: [],
            environment: localEnvironment(),
            execName: "zsh",
            currentDirectory: AppSettings.resolvedLocalShellCwd()
        )
        add(session)
    }

    private func localEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil {
            let identifier = Locale.current.identifier.replacingOccurrences(of: "_", with: "_")
            env["LANG"] = "\(identifier).UTF-8"
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    // MARK: SSH 会话

    @discardableResult
    func openSSH(to host: HostConfig, password: String, keyPassphrase: String) -> TerminalSession {
        let ssh = SSHSession(host: host)
        let view = MenuedTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.hideBuiltInScroller()
        theme(view, AppearanceCenter.isDark)

        let coordinator = SSHShellCoordinator()
        coordinator.session = ssh
        view.terminalDelegate = coordinator

        // 清屏：模拟器层直接清空（含滚动缓冲），再向远端发 Ctrl-L 重绘提示符
        view.onClearScreen = { [weak view, weak ssh] in
            view?.feed(text: "\u{1B}[3J\u{1B}[2J\u{1B}[H")
            ssh?.write(ArraySlice<UInt8>([0x0C]))
        }

        ssh.outputPipe.set { [weak view] bytes in
            view?.feed(byteArray: bytes)
        }
        ssh.onClosed = { [weak self, weak ssh] in
            guard let self, let ssh else { return }
            if self.activeSSH === ssh {
                self.activeSSH = self.aliveSSHs.first
            }
            self.onSSHDisconnected?(ssh)
        }

        let session = TerminalSession(
            kind: .ssh(ssh),
            view: view,
            title: host.displayTitle,
            coordinator: coordinator
        )
        session.bindTitle(from: ssh)

        ssh.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .connected {
                    self.activeSSH = ssh
                    self.onSSHConnected?(ssh)
                }
            }
            .store(in: &session.cancellables)

        add(session)
        ssh.connect(password: password, keyPassphrase: keyPassphrase)
        return session
    }

    // MARK: 通用

    func select(_ session: TerminalSession) {
        selectedID = session.id
        focus(session)
    }

    func focus(_ session: TerminalSession) {
        session.view.window?.makeFirstResponder(session.view)
    }

    func close(_ session: TerminalSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions.remove(at: index)
        }
        session.sshSession?.close()
        (session.view as? LocalProcessTerminalView)?.terminate()
        if selectedID == session.id {
            selectedID = sessions.last?.id
        }
        if let ssh = session.sshSession, activeSSH === ssh {
            activeSSH = aliveSSHs.first
        }
    }

    func applyThemeToAll(dark: Bool) {
        for session in sessions {
            (session.view as? TerminalView).map { theme($0, dark) }
        }
    }

    private func add(_ session: TerminalSession) {
        sessions.append(session)
        selectedID = session.id
    }
}

typealias TerminalThemeApplier = (TerminalView, Bool) -> Void
