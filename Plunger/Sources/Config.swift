import Foundation

func displayPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    guard path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}

struct Config: Codable {
    static let defaultPort: UInt16 = 54175

    /// The port a dev build always binds, ignoring the stored `port`. Dev and
    /// release share one UserDefaults domain, so a stored port would otherwise be
    /// shared between them; forcing this in DEBUG keeps a running dev build off
    /// the release build's port no matter what is saved.
    #if DEBUG
    static let devPort: UInt16 = 54176
    #endif

    var boundPort: UInt16 {
        #if DEBUG
        Self.devPort
        #else
        port
        #endif
    }

    static let defaultAllowedPeers: Set<PeerCategory> = [.loopback]

    static let defaultTerminal: Terminal = .ghostty

    var paths: [String] = []

    var launchFoldersInside: Set<String> = []

    var commands: [String] = []

    var rawCommands: [String] = []

    var terminal: Terminal = defaultTerminal

    var port: UInt16 = defaultPort

    var allowedPeers: Set<PeerCategory> = defaultAllowedPeers

    var authEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case paths, launchFoldersInside, commands, rawCommands, port, allowedPeers, authEnabled, terminal
    }

    init(
        paths: [String] = [],
        launchFoldersInside: Set<String> = [],
        commands: [String] = [],
        rawCommands: [String] = [],
        port: UInt16 = defaultPort,
        allowedPeers: Set<PeerCategory> = defaultAllowedPeers,
        authEnabled: Bool = true,
        terminal: Terminal = defaultTerminal
    ) {
        self.paths = paths
        self.launchFoldersInside = launchFoldersInside
        self.commands = commands
        self.rawCommands = rawCommands
        self.port = port
        self.allowedPeers = allowedPeers
        self.authEnabled = authEnabled
        self.terminal = terminal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paths = try container.decodeIfPresent([String].self, forKey: .paths) ?? []
        launchFoldersInside = try container.decodeIfPresent(Set<String>.self, forKey: .launchFoldersInside) ?? []
        commands = try container.decodeIfPresent([String].self, forKey: .commands) ?? []
        rawCommands = try container.decodeIfPresent([String].self, forKey: .rawCommands) ?? []
        port = try container.decodeIfPresent(UInt16.self, forKey: .port) ?? Self.defaultPort
        allowedPeers = try container.decodeIfPresent(Set<PeerCategory>.self, forKey: .allowedPeers)
            ?? Self.defaultAllowedPeers
        authEnabled = try container.decodeIfPresent(Bool.self, forKey: .authEnabled) ?? true
        terminal = try container.decodeIfPresent(Terminal.self, forKey: .terminal) ?? Self.defaultTerminal
    }
}

extension Array where Element == String {
    mutating func appendUnique(_ value: String) {
        guard !value.isEmpty, !contains(value) else { return }
        append(value)
    }

    func sortedForDisplay() -> [String] {
        sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
