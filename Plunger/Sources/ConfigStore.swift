import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ConfigStore {
    private static let configKey = "config"

    private(set) var config = Config()

    /// The shared bearer token for the local HTTP server. Stored (not computed
    /// off AuthToken) so @Observable views refresh when it is regenerated.
    private(set) var token: String

    private let defaults: UserDefaults
    private var authToken: AuthToken

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let authToken = AuthToken(defaults: defaults)
        self.authToken = authToken
        self.token = authToken.value
        load()
    }

    func regenerateToken() {
        token = authToken.regenerate()
    }

    func copyToken() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
    }

    var launchablePaths: [String] {
        PathExpansion.launchable(
            paths: config.paths,
            launchFoldersInside: config.launchFoldersInside
        )
    }

    func hasPath(_ path: String) -> Bool {
        launchablePaths.contains(path)
    }

    func launchesFoldersInside(_ path: String) -> Bool {
        config.launchFoldersInside.contains(path)
    }

    func hasCommand(_ command: String) -> Bool {
        config.commands.contains(command)
    }

    func hasRawCommand(_ command: String) -> Bool {
        config.rawCommands.contains(command)
    }

    private func load() {
        if let stored: Config = decode(Self.configKey) {
            config = stored
        }
    }

    private func save() {
        guard let data = try? PropertyListEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.configKey)
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? PropertyListDecoder().decode(T.self, from: data)
    }

    func addPath(_ path: String, launchFoldersInside: Bool = false) {
        config.paths.appendUnique(path)
        setLaunchFoldersInside(path, launchFoldersInside)
        save()
    }

    func addCommand(_ command: String) {
        config.commands.appendUnique(command)
        save()
    }

    func addRawCommand(_ command: String) {
        config.rawCommands.appendUnique(command)
        save()
    }

    func updatePath(_ path: String, to newPath: String, launchFoldersInside: Bool) {
        guard !newPath.isEmpty, newPath == path || !config.paths.contains(newPath) else { return }
        guard let index = config.paths.firstIndex(of: path) else { return }
        config.paths[index] = newPath
        config.launchFoldersInside.remove(path)
        setLaunchFoldersInside(newPath, launchFoldersInside)
        save()
    }

    private func setLaunchFoldersInside(_ path: String, _ enabled: Bool) {
        if enabled {
            config.launchFoldersInside.insert(path)
        } else {
            config.launchFoldersInside.remove(path)
        }
    }

    func updateCommand(_ command: String, to newCommand: String) {
        guard !newCommand.isEmpty, newCommand == command || !config.commands.contains(newCommand) else { return }
        guard let index = config.commands.firstIndex(of: command) else { return }
        config.commands[index] = newCommand
        save()
    }

    func deletePath(_ path: String) {
        config.paths.removeAll { $0 == path }
        config.launchFoldersInside.remove(path)
        save()
    }

    func deleteCommand(_ command: String) {
        config.commands.removeAll { $0 == command }
        save()
    }

    func updateRawCommand(_ command: String, to newCommand: String) {
        guard !newCommand.isEmpty, newCommand == command || !config.rawCommands.contains(newCommand) else { return }
        guard let index = config.rawCommands.firstIndex(of: command) else { return }
        config.rawCommands[index] = newCommand
        save()
    }

    func deleteRawCommand(_ command: String) {
        config.rawCommands.removeAll { $0 == command }
        save()
    }

    func setTerminal(_ terminal: Terminal) {
        guard terminal != config.terminal else { return }
        config.terminal = terminal
        save()
    }

    /// Sets the HTTP server port. A no-op when unchanged. The caller is
    /// responsible for restarting the server so the new port takes effect.
    func setPort(_ port: UInt16) {
        guard port != config.port else { return }
        config.port = port
        save()
    }

    func setAllowedPeers(_ peers: Set<PeerCategory>) {
        guard peers != config.allowedPeers else { return }
        config.allowedPeers = peers
        save()
    }

    func setAuthEnabled(_ enabled: Bool) {
        guard enabled != config.authEnabled else { return }
        config.authEnabled = enabled
        save()
    }
}
