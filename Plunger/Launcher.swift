import Foundation

enum Launcher {
    private static func appleScriptString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// Ghostty runs a configured `command` under `bash --noprofile --norc`,
    /// which sources none of the user's shell startup files, so the command
    /// inherits only the sparse PATH `login` sets from /etc/paths. Running it
    /// through `zsh -lic` sources .zprofile (login) and .zshrc (interactive),
    /// restoring the full PATH — Homebrew's `brew shellenv` line lives there.
    static func loginShellWrapped(_ command: String) -> String {
        let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "/bin/zsh -lic \(quoted)"
    }

    private static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

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

    static func launchRaw(path: String, command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", command]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        try? process.run()
    }
}
