import Foundation

struct AuthToken {
    private static let key = "httpServerToken"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var value: String {
        if let existing = defaults.string(forKey: Self.key), !existing.isEmpty {
            return existing
        }
        let token = Self.generate()
        defaults.set(token, forKey: Self.key)
        return token
    }

    @discardableResult
    mutating func regenerate() -> String {
        let token = Self.generate()
        defaults.set(token, forKey: Self.key)
        return token
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // Refuse the all-zero buffer: it would make the server token guessable.
            fatalError("Plunger: SecRandomCopyBytes failed to generate a token")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
