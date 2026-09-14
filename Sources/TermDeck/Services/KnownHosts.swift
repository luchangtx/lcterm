import Foundation
import Crypto
import NIOCore
import NIOSSH

/// 主机密钥指纹的本地记录（TOFU：Trust On First Use，与 OpenSSH known_hosts 同策略）
enum KnownHosts {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TermDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("known-hosts.json")
    }

    static func keyIdentifier(host: String, port: Int) -> String {
        "\(host):\(port)"
    }

    /// 计算 host key 的 SHA256 指纹（SSH wire 格式序列化后哈希）
    static func fingerprint(of key: NIOSSHPublicKey) -> String {
        var buffer = ByteBuffer()
        key.write(to: &buffer)
        let data = Data(buffer.readableBytesView)
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    static func recordedFingerprint(host: String, port: Int) -> String? {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return store[keyIdentifier(host: host, port: port)]
    }

    static func record(_ fingerprint: String, host: String, port: Int) {
        var store: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            store = decoded
        }
        store[keyIdentifier(host: host, port: port)] = fingerprint
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// 删除某主机的指纹记录（重新信任该主机用）
    static func remove(host: String, port: Int) {
        guard var store: [String: String] = (try? Data(contentsOf: fileURL)).flatMap({
            try? JSONDecoder().decode([String: String].self, from: $0)
        }) else { return }
        guard store.removeValue(forKey: keyIdentifier(host: host, port: port)) != nil else { return }
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

/// 主机密钥变化（疑似中间人攻击）错误
struct HostKeyChangedError: LocalizedError {
    let host: String
    let port: Int
    let fingerprint: String

    var errorDescription: String? {
        """
        服务器 \(host):\(port) 的主机密钥与首次连接时记录的不一致！\
        可能是服务器重装了系统，也可能存在中间人攻击。\
        如确认是服务器正常变更，请在侧栏删除该主机后重新添加以重新信任。
        """
    }
}

/// TOFU 主机密钥校验器：首次记录指纹，之后严格比对
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let fingerprint = KnownHosts.fingerprint(of: hostKey)

        if let recorded = KnownHosts.recordedFingerprint(host: host, port: port) {
            if recorded == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyChangedError(
                    host: host, port: port, fingerprint: fingerprint
                ))
            }
        } else {
            // 首次连接：记录并信任
            KnownHosts.record(fingerprint, host: host, port: port)
            validationCompletePromise.succeed(())
        }
    }
}
