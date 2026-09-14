import Foundation
import CryptoKit

/// 本地加密的秘密存储：替代钥匙串，避免每次连接弹出钥匙串授权框。
/// - 主密钥保存在 Application Support/TermDeck/.secret-key（权限 600）
/// - 机密以 AES-GCM 加密后存入 secrets.json（权限 600）
/// - 数据不出本机、不上传
enum SecureStore {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TermDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var keyURL: URL {
        directory.appendingPathComponent(".secret-key")
    }

    private static var storeURL: URL {
        directory.appendingPathComponent("secrets.json")
    }

    private static let key = loadKey()

    private static var cache: [String: String]?
    private static let cacheLock = NSLock()

    private static func loadKey() -> SymmetricKey {
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try? data.write(to: keyURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return key
    }

    private static func loadStore() -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache { return cache }
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    private static func persist(_ store: [String: String]) {
        cacheLock.lock()
        cache = store
        cacheLock.unlock()
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: storeURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
    }

    static func save(_ secret: String, account: String) {
        guard let sealed = try? AES.GCM.seal(Data(secret.utf8), using: key).combined else { return }
        var store = loadStore()
        store[account] = sealed.base64EncodedString()
        persist(store)
    }

    static func read(account: String) -> String? {
        guard let base64 = loadStore()[account],
              let data = Data(base64Encoded: base64),
              let sealed = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(sealed, using: key),
              let string = String(data: opened, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func delete(account: String) {
        var store = loadStore()
        guard store.removeValue(forKey: account) != nil else { return }
        persist(store)
    }
}
