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
