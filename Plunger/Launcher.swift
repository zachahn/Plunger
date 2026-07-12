//
//  Launcher.swift
//  Plunger
//
//  Opens a Ghostty terminal tab for a (path, command) pair by running an
//  AppleScript via osascript.
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

    /// Wraps `command` so Ghostty runs it under a login+interactive zsh.
    ///
    /// Ghostty runs a configured `command` under `bash --noprofile --norc`,
    /// which sources none of the user's shell startup files, so the command
    /// inherits only the sparse PATH `login` sets from /etc/paths. Running it
    /// through `zsh -lic` sources .zprofile (login) and .zshrc (interactive),
    /// restoring the full PATH — Homebrew's `brew shellenv` line lives there.
    static func loginShellWrapped(_ command: String) -> String {
        // Single-quote the command for the shell, escaping embedded quotes.
        let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "/bin/zsh -lic \(quoted)"
    }

    /// Single-quotes a string for the shell, escaping embedded quotes, so it can
    /// be pasted into a shell line as one literal argument.
    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Opens a terminal tab at `path` running `command`: a new window when none
    /// are open, otherwise a new tab in the front window. `terminal` selects the
    /// AppleScript dialect.
    static func launch(path: String, command: String, terminal: Terminal) {
        let script: String
        switch terminal {
        case .ghostty:
            script = ghosttyScript(path: path, command: command)
        case .iterm:
            script = itermScript(path: path, command: command)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    /// Ghostty passes `command` as a config value, wrapped by `loginShellWrapped`
    /// so it inherits the user's full PATH.
    private static func ghosttyScript(path: String, command: String) -> String {
        let path = appleScriptString(path)
        let command = appleScriptString(loginShellWrapped(command))
        return """
        tell application "Ghostty"
            if (count of windows) = 0 then
                new window with configuration {initial working directory:\(path), command:\(command)}
            else
                new tab in (front window) with configuration {initial working directory:\(path), command:\(command)}
            end if
        end tell
        """
    }

    /// iTerm has no working-directory/command config, so the shell line
    /// `cd <path>; clear; <command>` is written into a fresh window's session.
    /// The whole line is one AppleScript string literal.
    private static func itermScript(path: String, command: String) -> String {
        let line = appleScriptString("cd \(shellQuote(path)); clear; \(command)")
        return """
        tell application "iTerm"
            set newWindow to (create window with default profile)
            tell current session of newWindow
                write text \(line)
            end tell
        end tell
        """
    }

    /// Runs an already-interpolated raw `command` directly under a login+
    /// interactive zsh, with no terminal window, in `path` as the working
    /// directory.
    static func launchRaw(path: String, command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", command]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        try? process.run()
    }
}
