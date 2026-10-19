import Foundation
import Security
import ActivityKit

// Shared by the app and the widget extension.

/// Live Activity for a running breastfeeding or pumping timer, or a sleep.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// For example "Breastfeeding · Left side" or "Sleeping".
        var title: String
        var animal: String
        /// The timer counts up from this moment.
        var startedAt: Date
        /// Hex color for the accent, like 0xE8566C.
        var color: UInt32
    }

    /// "feed" or "sleep".
    var kind: String
    var babyName: String
}

/// What the home screen widget shows. The app writes it whenever entries change.
struct WidgetSnapshot: Codable {
    var babyName: String
    var lastFeed: Date?
    var lastFeedDetail: String?
    var nextSide: String?
    var lastDiaper: Date?
    var lastDiaperDetail: String?
    var sleepingSince: Date?
    var updated: Date

    private static let account = "widget-snapshot"

    /// The keychain group both the app and the widget can read, set in Info.plist.
    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "LittleLogSharedKeychainGroup") as? String
    }

    private static func query() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "LittleLogWidget",
            kSecAttrAccount as String: account,
        ]
        if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    static func load() -> WidgetSnapshot? {
        var query = query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let query = Self.query()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(query() as CFDictionary)
    }
}
