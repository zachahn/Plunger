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
    var paths: [String] = []
    var commands: [String] = []
}

extension Array where Element == String {
    /// Appends `value` unless it is empty or already present, mirroring the Go
    /// `appendUnique` helper. The pick-lists hold no blanks and no duplicates.
    mutating func appendUnique(_ value: String) {
        guard !value.isEmpty, !contains(value) else { return }
        append(value)
    }
}
