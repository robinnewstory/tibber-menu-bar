import Foundation
import Security

/// The Tibber access token, kept in the login keychain as a generic password owned by this app.
public struct TokenStore: Sendable {
    public static let service = "nl.newstory.tibber-menu-bar"
    public static let account = "access_token"

    public typealias Reader = @Sendable () throws -> String?
    public typealias Writer = @Sendable (String?) throws -> Void
    let read: Reader
    let write: Writer

    public init(read: @escaping Reader, write: @escaping Writer) {
        self.read = read
        self.write = write
    }

    public static let keychain = TokenStore(
        read: {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            return String(data: data, encoding: .utf8)
        },
        write: { value in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            guard let value, !value.isEmpty else {
                SecItemDelete(query as CFDictionary)
                return
            }
            let data = Data(value.utf8)
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var add = query
                add[kSecValueData as String] = data
                add[kSecAttrLabel as String] = "Tibber Menu Bar access token"
                let addStatus = SecItemAdd(add as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus)) }
            } else if status != errSecSuccess {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }
    )

    public func load() throws -> String? { try read()?.trimmingCharacters(in: .whitespacesAndNewlines) }
    public func save(_ token: String?) throws { try write(token?.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

/// Last fetched prices on disk, so the menu bar shows something immediately after launch.
public struct PriceCache {
    public let url: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TibberMenuBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("prices.json")
    }

    public func load() -> PriceData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(PriceData.self, from: data)
    }

    public func save(_ prices: PriceData) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(prices) { try? data.write(to: url, options: .atomic) }
    }
}
