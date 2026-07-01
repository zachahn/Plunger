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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
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

    /// Records a tuple and folds its path and command into the pick-lists. The
    /// command's program is resolved to an absolute path here, at create time.
    func addEntry(_ entry: Entry) {
        var entry = entry
        entry.command = CommandResolver.resolveCommand(entry.command)
        config.entries.append(entry)
        config.paths.appendUnique(entry.path)
        config.commands.appendUnique(entry.command)
        save()
    }

    func updateEntry(at index: Int, with entry: Entry) {
        guard config.entries.indices.contains(index) else { return }
        var entry = entry
        entry.command = CommandResolver.resolveCommand(entry.command)
        config.entries[index] = entry
        config.paths.appendUnique(entry.path)
        config.commands.appendUnique(entry.command)
        save()
    }

    func deleteEntry(at index: Int) {
        guard config.entries.indices.contains(index) else { return }
        config.entries.remove(at: index)
        save()
    }

    func addPath(_ path: String) {
        config.paths.appendUnique(path)
        save()
    }

    func addCommand(_ command: String) {
        config.commands.appendUnique(CommandResolver.resolveCommand(command))
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
