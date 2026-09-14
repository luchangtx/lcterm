import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

enum ConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
    case closed
}

enum SSHError {
    static func describe(_ error: Error) -> String {
        let text = String(describing: error) + " " + error.localizedDescription
        if text.contains("Connection refused") { return "连接被拒绝，请检查主机地址和端口" }
        if text.lowercased().contains("auth") { return "认证失败，请检查用户名、密码或私钥" }
        if text.lowercased().contains("timed out") || text.lowercased().contains("timeout") { return "连接超时，请检查网络与防火墙" }
        if text.contains("missingDecryptionKey") { return "私钥已加密，需要提供口令（passphrase）" }
        if let hostKeyError = error as? HostKeyChangedError {
            return hostKeyError.errorDescription ?? "主机密钥校验失败"
        }
        if text.contains("InvalidHostKey") || text.contains("Invalid host key") { return "主机密钥校验失败" }
        if text.contains("channelCreationFailed") { return "无法建立 SSH 通道" }
        let message = error.localizedDescription
        return message.isEmpty ? String(describing: error) : message
    }
}

enum SSHConnectError: LocalizedError {
    case keyFileUnreadable(String)
    case keyUnsupported

    var errorDescription: String? {
        switch self {
        case .keyFileUnreadable(let path): return "无法读取私钥文件：\(path)"
        case .keyUnsupported: return "私钥格式不支持（目前支持 OpenSSH 格式的 Ed25519 / RSA 密钥）"
        }
    }
}

struct TermSize: Equatable {
    var cols: Int = 80
    var rows: Int = 24
}

/// 跨线程安全地把远端输出转发到主线程
final class OutputPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((ArraySlice<UInt8>) -> Void)?

    func set(_ handler: @escaping (ArraySlice<UInt8>) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func emit(_ bytes: [UInt8]) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { return }
        if Thread.isMainThread {
            handler(bytes[...])
        } else {
            DispatchQueue.main.async { handler(bytes[...]) }
        }
    }
}

/// 一次 SSH 连接 = 终端 PTY 会话 + SFTP 通道
@MainActor
final class SSHSession: ObservableObject, Identifiable {
    let id = UUID()
    let host: HostConfig
    @Published private(set) var state: ConnectionState = .idle
    @Published var title: String

    /// 终端 view 通过它接收远端输出（主线程回调）
    let outputPipe = OutputPipe()
    var onClosed: (() -> Void)?

    /// 每个连接拥有独立的文件浏览器
    let fileBrowser = RemoteFileBrowser()

    private let clientBox = Protected<SSHClient?>(nil)
    private let writerBox = Protected<TTYStdinWriter?>(nil)
    private let sftpBox = Protected<SFTPClient?>(nil)
    private let inputBox = Protected<AsyncStream<ByteBuffer>.Continuation?>(nil)
    private let sizeBox = Protected(TermSize())
    private var shellTask: Task<Void, Never>?
    private var generation = 0
    private var lastSecret: (password: String, keyPassphrase: String) = ("", "")
    private(set) var lastConnectError: Error?

    init(host: HostConfig) {
        self.host = host
        self.title = host.displayTitle
        fileBrowser.bind(session: self)
    }

    nonisolated var sftpClient: SFTPClient? { sftpBox.get() }

    // MARK: - 认证

    static func makeAuthenticationMethod(
        host: HostConfig,
        password: String,
        keyPassphrase: String
    ) throws -> SSHAuthenticationMethod {
        switch host.authMethod {
        case .password:
            return .passwordBased(username: host.username, password: password)
        case .privateKey(let keyPath):
            guard let keyString = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
                throw SSHConnectError.keyFileUnreadable(keyPath)
            }
            let passphraseData = keyPassphrase.isEmpty ? nil : Data(keyPassphrase.utf8)
            do {
                let key = try Curve25519.Signing.PrivateKey(sshEd25519: keyString, decryptionKey: passphraseData)
                return .ed25519(username: host.username, privateKey: key)
            } catch {
                let key = try Insecure.RSA.PrivateKey(sshRsa: keyString, decryptionKey: passphraseData)
                return .rsa(username: host.username, privateKey: key)
            }
        }
    }

    // MARK: - 连接

    func connect(password: String, keyPassphrase: String = "") {
        generation += 1
        let gen = generation
        lastSecret = (password, keyPassphrase)
        lastConnectError = nil
        closeTransport()
        state = .connecting

        let host = self.host
        shellTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let method = try Self.makeAuthenticationMethod(
                    host: host, password: password, keyPassphrase: keyPassphrase
                )
                var settings = SSHClientSettings(
                    host: host.host,
                    port: host.port,
                    authenticationMethod: { method },
                    hostKeyValidator: .custom(TOFUHostKeyValidator(host: host.host, port: host.port))
                )
                settings.connectTimeout = .seconds(15)

                let client = try await SSHClient.connect(to: settings)
                guard !Task.isCancelled, self.generation == gen else {
                    try? await client.close()
                    return
                }
                self.clientBox.set(client)

                client.onDisconnect { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.handleRemoteClose(generation: gen)
                    }
                }

                // SFTP 通道：失败不阻塞终端
                if let sftp = try? await client.openSFTP() {
                    self.sftpBox.set(sftp)
                    self.fileBrowser.markAvailable()
                }

                guard self.generation == gen, self.state != .closed else {
                    try? await client.close()
                    return
                }
                self.state = .connected

                let size = self.sizeBox.get()
                let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: size.cols,
                    terminalRowHeight: size.rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([:])
                )

                let (inputStream, inputContinuation) = AsyncStream<ByteBuffer>.makeStream()
                self.inputBox.set(inputContinuation)

                do {
                    try await client.withPTY(ptyRequest) { inbound, outbound in
                        self.writerBox.set(outbound)

                        // 连接建立时同步一次实际终端尺寸
                        let current = self.sizeBox.get()
                        if current != size {
                            Task {
                                try? await outbound.changeSize(
                                    cols: current.cols, rows: current.rows,
                                    pixelWidth: 0, pixelHeight: 0
                                )
                            }
                        }

                        let pumpTask = Task {
                            for await chunk in inputStream {
                                do {
                                    try await outbound.write(chunk)
                                } catch {
                                    break
                                }
                            }
                        }
                        defer {
                            inputContinuation.finish()
                            pumpTask.cancel()
                        }

                        for try await output in inbound {
                            switch output {
                            case .stdout(let buffer):
                                self.outputPipe.emit(Array(buffer.readableBytesView))
                            case .stderr(let buffer):
                                self.outputPipe.emit(Array(buffer.readableBytesView))
                            }
                        }
                    }
                    self.handleRemoteClose(generation: gen)
                } catch {
                    self.inputBox.set(nil)
                    if !Task.isCancelled, self.generation == gen {
                        self.lastConnectError = error
                        self.state = .failed("终端会话中断：\(SSHError.describe(error))")
                    }
                }
            } catch {
                if !Task.isCancelled, self.generation == gen {
                    self.lastConnectError = error
                    self.state = .failed(SSHError.describe(error))
                }
            }
        }
    }

    func retry() {
        connect(password: lastSecret.password, keyPassphrase: lastSecret.keyPassphrase)
    }

    /// 确认服务器密钥变更后，清除旧指纹重新信任并连接
    func retrustAndReconnect() {
        KnownHosts.remove(host: host.host, port: host.port)
        retry()
    }

    func close() {
        generation += 1
        closeTransport()
        if case .failed = state {
            // 保留失败信息供界面展示
        } else {
            state = .closed
        }
        onClosed?()
    }

    /// 断开底层传输（输入流、任务、连接），不动状态
    private func closeTransport() {
        inputBox.get()?.finish()
        inputBox.set(nil)
        shellTask?.cancel()
        shellTask = nil
        let client = clientBox.get()
        clientBox.set(nil)
        sftpBox.set(nil)
        writerBox.set(nil)
        if let client {
            Task.detached {
                try? await client.close()
            }
        }
    }

    private func handleRemoteClose(generation gen: Int) {
        guard gen == generation else { return }
        guard state == .connecting || state == .connected else { return }
        closeTransport()
        state = .closed
        onClosed?()
    }

    // MARK: - 终端 I/O

    nonisolated func write(_ bytes: ArraySlice<UInt8>) {
        inputBox.get()?.yield(ByteBuffer(bytes: Array(bytes)))
    }

    nonisolated func noteSize(cols: Int, rows: Int) {
        sizeBox.with { $0 = TermSize(cols: cols, rows: rows) }
    }

    nonisolated func resize(cols: Int, rows: Int) {
        noteSize(cols: cols, rows: rows)
        let writer = writerBox.get()
        guard writer != nil else { return }
        Task {
            try? await writer?.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        }
    }
}
