//
//  Prompt.swift
//  Plunger
//
//  Native system panels used outside the SwiftUI edit panel.
//

import AppKit

enum Prompt {
    /// Shows the OS directory picker and returns the chosen directory's path.
    /// Returns nil when the user cancels. `initialDirectory`, when given, opens
    /// the picker there instead of its default location, for editing in place.
    @MainActor
    static func directory(title: String, initialDirectory: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let initialDirectory {
            panel.directoryURL = URL(fileURLWithPath: initialDirectory)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
