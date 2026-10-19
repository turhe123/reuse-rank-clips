import Foundation

/// A single captured text clip together with its reuse statistics.
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var key: String
    var text: String
    var label: String?
    var count: Int
    var created: Date
    var lastUsed: Date
    var pinned = false
    var promoted = false
    /// Use count at the moment the item was last demoted; re-promotion needs `threshold` more uses.
    var demotedAtCount = 0
    var sourceApp: String?

    /// A bounded slice of the text for list rendering (full text is always kept).
    var preview: String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }

    var hasLabel: Bool { !(label ?? "").isEmpty }
}

/// Normalizes clip text and derives a stable key so repeated copies map to a single record.
enum ClipKey {
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = Substring(line)
                while let last = s.last, last.isWhitespace { s = s.dropLast() }
                return String(s)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 64-bit FNV-1a hash of the normalized text, plus its length to make collisions negligible.
    static func hash(_ text: String) -> String {
        let normalized = normalize(text)
        var h: UInt64 = 0xcbf29ce484222325
        for byte in normalized.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return "\(String(h, radix: 16))-\(normalized.utf8.count)"
    }
}

/// UserDefaults keys and defaults shared by `@AppStorage` and the services.
enum Prefs {
    enum Key {
        static let threshold = "promotionThreshold"
        static let historySize = "historySize"
        static let retentionDays = "retentionDays"
        static let pasteImmediately = "pasteImmediately"
        static let ignoredApps = "ignoredApps"
        static let hotkeyCode = "hotkeyCode"
        static let hotkeyMods = "hotkeyModifiers"
        static let hotkeyName = "hotkeyName"
        static let didExplainAX = "didExplainAccessibility"
    }

    static let defaultIgnoredApps = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
    ].joined(separator: "\n")

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.threshold: 3,
            Key.historySize: 200,
            Key.retentionDays: 30,
            Key.pasteImmediately: true,
            Key.ignoredApps: defaultIgnoredApps,
            Key.hotkeyCode: 9,              // V
            Key.hotkeyMods: 256 | 512,      // ⌘⇧
            Key.hotkeyName: "⌘⇧V",
        ])
    }

    static var threshold: Int { max(1, UserDefaults.standard.integer(forKey: Key.threshold)) }
    static var historySize: Int { max(10, UserDefaults.standard.integer(forKey: Key.historySize)) }
    static var retentionDays: Int { UserDefaults.standard.integer(forKey: Key.retentionDays) }
    static var pasteImmediately: Bool { UserDefaults.standard.bool(forKey: Key.pasteImmediately) }

    static var ignoredApps: Set<String> {
        let raw = UserDefaults.standard.string(forKey: Key.ignoredApps) ?? ""
        return Set(raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
