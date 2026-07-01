//
//  ConfigStore.swift
//  Plunger
//
//  Owns the Config and persists it to UserDefaults. Ported from the Go app's
//  loadConfig/saveConfig and the per-mutation helpers. The Go program stored the
//  struct as a property-list blob under the "config" key; this keeps the same key
//  and encoding so an existing oiio defaults file would still read.
//

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

    // MARK: - Token

    /// Replaces the HTTP server token with a fresh random one. Clients using the
    /// old token stop working until they pick up the new value.
    func regenerateToken() {
        token = authToken.regenerate()
    }

    // MARK: - Read-only queries

    /// Reports whether `path` is one of the saved paths.
    func hasPath(_ path: String) -> Bool {
        config.paths.contains(path)
    }

    /// Reports whether `command` is one of the saved commands.
    func hasCommand(_ command: String) -> Bool {
        config.commands.contains(command)
    }

    // MARK: - Persistence

    /// Reads the config from UserDefaults.
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

    // MARK: - Mutations

    func addPath(_ path: String) {
        config.paths.appendUnique(path)
        save()
    }

    func addCommand(_ command: String) {
        config.commands.appendUnique(command)
        save()
    }

    /// Rewrites `path` to `newPath` in place, preserving its position. A no-op
    /// when `path` isn't saved, `newPath` is blank, or `newPath` is already
    /// saved.
    func updatePath(_ path: String, to newPath: String) {
        guard !newPath.isEmpty, newPath == path || !config.paths.contains(newPath) else { return }
        guard let index = config.paths.firstIndex(of: path) else { return }
        config.paths[index] = newPath
        save()
    }

    /// Rewrites `command` to `newCommand` in place, preserving its position.
    /// A no-op when `command` isn't saved, `newCommand` is blank, or
    /// `newCommand` is already saved.
    func updateCommand(_ command: String, to newCommand: String) {
        guard !newCommand.isEmpty, newCommand == command || !config.commands.contains(newCommand) else { return }
        guard let index = config.commands.firstIndex(of: command) else { return }
        config.commands[index] = newCommand
        save()
    }

    func deletePath(_ path: String) {
        config.paths.removeAll { $0 == path }
        save()
    }

    func deleteCommand(_ command: String) {
        config.commands.removeAll { $0 == command }
        save()
    }

    /// Sets the HTTP server port. A no-op when unchanged. The caller is
    /// responsible for restarting the server so the new port takes effect.
    func setPort(_ port: UInt16) {
        guard port != config.port else { return }
        config.port = port
        save()
    }

    /// Sets the source networks the server accepts. Takes effect on the next
    /// connection; no restart needed, since the server reads it per request.
    func setAllowedPeers(_ peers: Set<PeerCategory>) {
        guard peers != config.allowedPeers else { return }
        config.allowedPeers = peers
        save()
    }

    /// Sets whether the HTTP server requires the bearer token. Takes effect on
    /// the next connection; no restart needed, since the server reads it per
    /// request.
    func setAuthEnabled(_ enabled: Bool) {
        guard enabled != config.authEnabled else { return }
        config.authEnabled = enabled
        save()
    }
}
