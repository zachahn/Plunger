//
//  Config.swift
//  Plunger
//
//  The persisted state: pick-lists of paths and commands, stored as a
//  property-list blob in macOS user defaults.
//

import Foundation

/// Abbreviates the home directory to `~` for display. The underlying path is
/// left untouched; this is purely cosmetic.
func displayPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    guard path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}

struct Config: Codable {
    /// The default HTTP server port.
    static let defaultPort: UInt16 = 8765

    /// The source networks allowed by default: this Mac only. Users open up LAN
    /// or tailnet access from the HTTP Server settings tab.
    static let defaultAllowedPeers: Set<PeerCategory> = [.loopback]

    var paths: [String] = []
    var commands: [String] = []

    /// The port the local HTTP server binds. Decodes to `defaultPort` for older
    /// stored configs that predate this field.
    var port: UInt16 = defaultPort

    /// Source networks the server accepts connections from (on top of the token).
    /// Decodes to `defaultAllowedPeers` for older configs that predate the field.
    var allowedPeers: Set<PeerCategory> = defaultAllowedPeers

    /// Whether the HTTP server requires the bearer token. Decodes to `true` for
    /// older configs that predate the field, preserving prior behavior.
    var authEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case paths, commands, port, allowedPeers, authEnabled
    }

    init(
        paths: [String] = [],
        commands: [String] = [],
        port: UInt16 = defaultPort,
        allowedPeers: Set<PeerCategory> = defaultAllowedPeers,
        authEnabled: Bool = true
    ) {
        self.paths = paths
        self.commands = commands
        self.port = port
        self.allowedPeers = allowedPeers
        self.authEnabled = authEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        commands = try container.decodeIfPresent([String].self, forKey: .commands) ?? []
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? Self.defaultPort
        allowedPeers = try container.decodeIfPresent(Set<PeerCategory>.self, forKey: .allowedPeers)
            ?? Self.defaultAllowedPeers
        authEnabled = try container.decodeIfPresent(Bool.self, forKey: .authEnabled) ?? true
    }
}

extension Array where Element == String {
    /// Appends `value` unless it is empty or already present. The pick-lists
    /// hold no blanks and no duplicates.
    mutating func appendUnique(_ value: String) {
        guard !value.isEmpty, !contains(value) else { return }
        append(value)
    }

    /// Sorts case-insensitively for display. The stored order in ConfigStore
    /// (insertion order) is left untouched; this is presentation only, and is
    /// the one place every UI (menu bar, settings panel, web form) sorts
    /// paths and commands, so they stay consistent.
    func sortedForDisplay() -> [String] {
        sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
