//
//  Terminal.swift
//  Plunger
//
//  Names the terminal app a launch targets. `Launcher` uses `appName` in the
//  AppleScript `tell application` clause; the UI uses `label` for display.
//

import Foundation

enum Terminal: String, Codable, CaseIterable, Identifiable {
    case ghostty
    case iterm

    var id: String { rawValue }

    /// Display name shown in the UI.
    var label: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm"
        }
    }

    /// Name used in AppleScript's `tell application "..."` clause.
    var appName: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm"
        }
    }
}
