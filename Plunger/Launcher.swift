//
//  Launcher.swift
//  Plunger
//
//  Opens a Ghostty terminal tab for an entry by running an AppleScript via
//  osascript. Ported from the Go app's launchEntry and appleScriptString.
//

import Foundation

enum Launcher {
    /// Escapes a Swift string as an AppleScript string literal, including quotes.
    private static func appleScriptString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// Opens the entry in Ghostty: a new window when none are open, otherwise a
    /// new tab in the front window.
    static func launch(_ entry: Entry) {
        let path = appleScriptString(entry.path)
        let command = appleScriptString(entry.command)
        let script = """
        tell application "Ghostty"
            if (count of windows) = 0 then
                new window with configuration {initial working directory:\(path), command:\(command)}
            else
                new tab in (front window) with configuration {initial working directory:\(path), command:\(command)}
            end if
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
