import Foundation

@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [HostConfig] = []

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TermDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hosts.json")
    }

    init() {
        load()
        migrateKeychainSecretsIfNeeded()
    }

    /// 历史版本把密码存在钥匙串（每次连接会弹授权框）。启动时一次性迁移到本地加密存储。
    private func migrateKeychainSecretsIfNeeded() {
        for host in hosts {
            for kind in [SecretKind.password, .passphrase] {
                let account = secretAccount(host.id, kind: kind)
                guard SecureStore.read(account: account) == nil else {
                    KeychainStore.delete(account: account)
                    continue
                }
                if let value = KeychainStore.read(account: account), !value.isEmpty {
                    SecureStore.save(value, account: account)
                }
                KeychainStore.delete(account: account)
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        hosts = (try? JSONDecoder().decode([HostConfig].self, from: data)) ?? []
        hosts.sort { $0.createdAt < $1.createdAt }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func save(_ host: HostConfig) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        persist()
    }

    func remove(_ host: HostConfig) {
        hosts.removeAll { $0.id == host.id }
        KeychainStore.delete(account: secretAccount(host.id, kind: .password))
        KeychainStore.delete(account: secretAccount(host.id, kind: .passphrase))
        persist()
    }

    // MARK: - 分组

    /// 按出现顺序去重的分组名（空分组排最后，用 "" 表示）
    var groupNames: [String] {
        var seen: [String] = []
        for host in hosts {
            let group = host.trimmedGroup
            if !seen.contains(group) { seen.append(group) }
        }
        let named = seen.filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return seen.contains("") ? named + [""] : named
    }

    func hosts(inGroup group: String) -> [HostConfig] {
        hosts.filter { $0.trimmedGroup == group }
    }

    // MARK: - 敏感信息（钥匙串）

    enum SecretKind: String {
        case password, passphrase
    }

    func secretAccount(_ id: UUID, kind: SecretKind) -> String {
        "\(id.uuidString).\(kind.rawValue)"
    }

    func savePassword(_ id: UUID, _ secret: String) {
        SecureStore.save(secret, account: secretAccount(id, kind: .password))
    }

    func password(_ id: UUID) -> String? {
        SecureStore.read(account: secretAccount(id, kind: .password))
    }

    func savePassphrase(_ id: UUID, _ secret: String) {
        SecureStore.save(secret, account: secretAccount(id, kind: .passphrase))
    }

    func passphrase(_ id: UUID) -> String? {
        SecureStore.read(account: secretAccount(id, kind: .passphrase))
    }
}
