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
    private static let legacyEntriesKey = "entries" // flat [Entry], read once for migration

    private(set) var config = Config()

    private let defaults: UserDefaults
    private let authToken: AuthToken

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.authToken = AuthToken(defaults: defaults)
        load()
    }

    // MARK: - Read-only queries

    /// The shared bearer token for the local HTTP server.
    var token: String { authToken.value }

    /// Reports whether `path` is one of the saved paths.
    func hasPath(_ path: String) -> Bool {
        config.paths.contains(path)
    }

    /// Reports whether `command` is one of the saved commands.
    func hasCommand(_ command: String) -> Bool {
        config.commands.contains(command)
    }

    // MARK: - Persistence

    /// Reads the config, migrating the legacy flat entries list on first run, and
    /// seeds the pick-lists from existing entries so an upgrade never starts blank.
    private func load() {
        if let stored: Config = decode(Self.configKey) {
            config = stored
        }

        if config.entries.isEmpty, config.paths.isEmpty, config.commands.isEmpty,
           let legacy: [Entry] = decode(Self.legacyEntriesKey) {
            config.entries = legacy
        }

        for entry in config.entries {
            config.paths.appendUnique(entry.path)
            config.commands.appendUnique(entry.command)
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

    func deletePath(_ path: String) {
        config.paths.removeAll { $0 == path }
        save()
    }

    func deleteCommand(_ command: String) {
        config.commands.removeAll { $0 == command }
        save()
    }
}
