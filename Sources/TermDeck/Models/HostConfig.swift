import Foundation

struct HostConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authMethod: AuthMethod = .password
    var group: String = ""
    var createdAt: Date = Date()

    enum AuthMethod: Codable, Hashable {
        case password
        case privateKey(keyPath: String)

        var isKey: Bool {
            if case .privateKey = self { return true }
            return false
        }

        var keyPath: String? {
            if case .privateKey(let path) = self { return path }
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, authMethod, group, createdAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .password
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var trimmedGroup: String {
        group.trimmingCharacters(in: .whitespaces)
    }

    var displayTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "\(username)@\(host)" : trimmed
    }
}
