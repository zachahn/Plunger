//
//  Config.swift
//  Plunger
//
//  The persisted state: saved (path, command) tuples plus reusable pick-lists
//  of paths and commands. Ported from the Go app's `config` struct, which stored
//  the same shape in macOS user defaults.
//

import Foundation

struct Entry: Codable, Hashable, Identifiable {
    var path: String
    var command: String

    var id: String { path + "\u{0}" + command }

    var label: String { path + ": " + command }

    /// Like `label`, but abbreviates the home directory to `~` for display.
    var displayLabel: String { displayPath(path) + ": " + command }
}

/// Abbreviates the home directory to `~` for display. The underlying path is
/// left untouched; this is purely cosmetic.
func displayPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    guard path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}

struct Config: Codable {
    var paths: [String] = []
    var commands: [String] = []
    var entries: [Entry] = []
}

extension Array where Element == String {
    /// Appends `value` unless it is empty or already present, mirroring the Go
    /// `appendUnique` helper. The pick-lists hold no blanks and no duplicates.
    mutating func appendUnique(_ value: String) {
        guard !value.isEmpty, !contains(value) else { return }
        append(value)
    }
}
