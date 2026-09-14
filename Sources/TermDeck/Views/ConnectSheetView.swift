import SwiftUI
import AppKit

struct ConnectSheetView: View {
    let mode: AppSheet.Mode
    @State private var config: HostConfig
    @State private var portText: String
    @State private var password = ""
    @State private var keyPassphrase = ""
    @State private var isKeyAuth: Bool
    @State private var keyPath: String
    @State private var group: String
    @State private var saveSecret = true
    @State private var errorMessage: String?
    @ObservedObject var hostStore: HostStore
    @ObservedObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    init(mode: AppSheet.Mode, host: HostConfig, hostStore: HostStore, sessionManager: SessionManager) {
        self.mode = mode
        self.hostStore = hostStore
        self.sessionManager = sessionManager
        _config = State(initialValue: host)
        _portText = State(initialValue: String(host.port))
        _isKeyAuth = State(initialValue: host.authMethod.isKey)
        _keyPath = State(initialValue: host.authMethod.keyPath ?? "")
        _group = State(initialValue: host.trimmedGroup)
    }

    private var isCredentialsOnly: Bool { mode == .credentials }

    private var title: String {
        switch mode {
        case .create: return "新建连接"
        case .edit: return "编辑连接"
        case .credentials: return "输入登录信息 · \(config.displayTitle)"
        }
    }

    private var connectTitle: String {
        mode == .credentials ? "连接" : "保存并连接"
    }

    private var canConnect: Bool {
        if !isCredentialsOnly {
            if config.host.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if config.username.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if isKeyAuth && keyPath.isEmpty { return false }
        }
        if !isKeyAuth {
            let hasStored = !(hostStore.password(config.id) ?? "").isEmpty
            if password.isEmpty && !hasStored { return false }
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            if !isCredentialsOnly {
                fieldRow("别名") {
                    TextField("可选，如：生产服务器（留空则显示 用户名@主机）", text: $config.name)
                }
                fieldRow("主机") {
                    TextField("example.com 或 IP 地址", text: $config.host)
                }
                HStack(spacing: 8) {
                    Text("端口")
                        .frame(width: 44, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("22", text: $portText)
                        .frame(width: 64)
                    Spacer()
                    Text("用户名")
                        .foregroundColor(.secondary)
                    TextField("root", text: $config.username)
                        .frame(width: 150)
                }
                fieldRow("认证") {
                    Picker("", selection: $isKeyAuth) {
                        Text("密码").tag(false)
                        Text("私钥").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    Spacer()
                }
                fieldRow("分组") {
                    TextField("如：生产环境 / 测试，可留空", text: $group)
                    if !hostStore.groupNames.filter({ !$0.isEmpty }).isEmpty {
                        Menu {
                            ForEach(hostStore.groupNames.filter { !$0.isEmpty }, id: \.self) { name in
                                Button(name) { group = name }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("选择已有分组")
                    }
                }
            }

            Group {
                if isKeyAuth {
                    fieldRow("私钥") {
                        TextField("~/.ssh/id_ed25519", text: $keyPath)
                            .disabled(isCredentialsOnly)
                        Button("浏览…") { pickKeyFile() }
                            .disabled(isCredentialsOnly)
                    }
                    fieldRow("口令") {
                        SecureField("私钥口令，无则留空", text: $keyPassphrase)
                    }
                } else {
                    fieldRow("密码") {
                        SecureField("登录密码", text: $password)
                    }
                }
            }

            Toggle(saveLabel, isOn: $saveSecret)
                .font(.caption)
                .padding(.leading, 52)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button(connectTitle, action: connectNow)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConnect)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var saveLabel: String {
        isKeyAuth ? "记住私钥口令" : "记住密码"
    }

    private func fieldRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 44, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
            Spacer(minLength: 0)
        }
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "选择 OpenSSH 私钥文件（如 ~/.ssh/id_ed25519）"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            keyPath = url.path
        }
    }

    private func connectNow() {
        var host = config
        host.name = host.name.trimmingCharacters(in: .whitespaces)
        host.host = host.host.trimmingCharacters(in: .whitespaces)
        host.username = host.username.trimmingCharacters(in: .whitespaces)
        host.port = Int(portText) ?? 22
        host.group = group.trimmingCharacters(in: .whitespaces)
        host.authMethod = isKeyAuth ? .privateKey(keyPath: keyPath) : .password

        if !isCredentialsOnly {
            guard !host.host.isEmpty else {
                errorMessage = "请填写主机地址"
                return
            }
            guard !host.username.isEmpty else {
                errorMessage = "请填写用户名"
                return
            }
            if isKeyAuth && keyPath.isEmpty {
                errorMessage = "请选择私钥文件"
                return
            }
        }

        // 已保存的密钥不因为留空而被覆盖
        let storedPassword = hostStore.password(host.id)
        let storedPassphrase = hostStore.passphrase(host.id)
        let passwordToUse = password.isEmpty ? (storedPassword ?? "") : password
        let passphraseToUse = keyPassphrase.isEmpty ? (storedPassphrase ?? "") : keyPassphrase

        if mode != .credentials {
            hostStore.save(host)
        }
        if saveSecret {
            if isKeyAuth {
                if !passphraseToUse.isEmpty || storedPassphrase != nil {
                    hostStore.savePassphrase(host.id, passphraseToUse)
                }
            } else {
                hostStore.savePassword(host.id, passwordToUse)
            }
        }

        sessionManager.openSSH(
            to: host,
            password: isKeyAuth ? "" : passwordToUse,
            keyPassphrase: isKeyAuth ? passphraseToUse : ""
        )
        dismiss()
    }
}
