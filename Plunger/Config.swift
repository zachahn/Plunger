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
    /// The default HTTP server port, matching the original Go app.
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

    enum CodingKeys: String, CodingKey {
        case paths, commands, port, allowedPeers
    }

    init(
        paths: [String] = [],
        commands: [String] = [],
        port: UInt16 = defaultPort,
        allowedPeers: Set<PeerCategory> = defaultAllowedPeers
    ) {
        self.paths = paths
        self.commands = commands
        self.port = port
        self.allowedPeers = allowedPeers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        commands = try container.decodeIfPresent([String].self, forKey: .commands) ?? []
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? Self.defaultPort
        allowedPeers = try container.decodeIfPresent(Set<PeerCategory>.self, forKey: .allowedPeers)
            ?? Self.defaultAllowedPeers
    }
}

extension Array where Element == String {
    /// Appends `value` unless it is empty or already present, mirroring the Go
    /// `appendUnique` helper. The pick-lists hold no blanks and no duplicates.
    mutating func appendUnique(_ value: String) {
        guard !value.isEmpty, !contains(value) else { return }
        append(value)
    }
}
