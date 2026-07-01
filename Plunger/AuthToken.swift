//
//  AuthToken.swift
//  Plunger
//
//  The shared bearer token that guards the local HTTP server. It is generated
//  once on first read, persisted in UserDefaults under its own key, and returned
//  unchanged thereafter. Keeping it here keeps token concerns out of the config
//  blob in ConfigStore.
//

import Foundation

struct AuthToken {
    private static let key = "httpServerToken"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the persisted token, generating and saving one on first read.
    var value: String {
        if let existing = defaults.string(forKey: Self.key), !existing.isEmpty {
            return existing
        }
        let token = Self.generate()
        defaults.set(token, forKey: Self.key)
        return token
    }

    /// Replaces the stored token with a fresh random one and returns it. Clients
    /// authenticating with the old token stop working until they pick up the new.
    @discardableResult
    mutating func regenerate() -> String {
        let token = Self.generate()
        defaults.set(token, forKey: Self.key)
        return token
    }

    /// 32 random bytes, base64url-encoded with no padding.
    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // The random source is unavailable; refuse to hand back the all-zero
            // buffer, which would be a fixed, guessable token guarding the server.
            fatalError("Plunger: SecRandomCopyBytes failed to generate a token")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
