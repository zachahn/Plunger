//
//  CommandResolver.swift
//  Plunger
//
//  Resolves a command's program to an absolute path. Ported from the Go app's
//  resolveProgram/resolveCommand. A GUI app launched from Finder inherits a
//  minimal PATH that usually lacks Homebrew, so the common bin directories are
//  searched explicitly.
//

import Foundation

enum CommandResolver {
    /// Searched when the program is not found on the process PATH.
    private static let commonBinDirs = [
        "/opt/homebrew/bin", // Apple Silicon Homebrew
        "/usr/local/bin",    // Intel Homebrew
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Looks up an absolute path for `program`. It tries the process PATH first,
    /// then the common bin directories. The original value is returned when
    /// nothing matches, so an unresolved command still launches and surfaces its
    /// own error.
    static func resolveProgram(_ program: String) -> String {
        if program.contains("/") {
            return program // already a path; leave it alone
        }
        if let onPath = lookPath(program) {
            return onPath
        }
        let fileManager = FileManager.default
        for dir in commonBinDirs {
            let candidate = (dir as NSString).appendingPathComponent(program)
            if fileManager.isExecutableFile(atPath: candidate) {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                   !isDirectory.boolValue {
                    return candidate
                }
            }
        }
        return program
    }

    /// Rewrites the program in a command string with its absolute path. The first
    /// token is resolved; the remaining arguments are preserved verbatim.
    static func resolveCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let spaceIndex = trimmed.firstIndex(of: " ") {
            let program = String(trimmed[..<spaceIndex])
            let rest = String(trimmed[trimmed.index(after: spaceIndex)...])
            return resolveProgram(program) + " " + rest
        }
        return resolveProgram(trimmed)
    }

    /// Walks the process PATH for an executable named `program`, like exec.LookPath.
    private static func lookPath(_ program: String) -> String? {
        guard let pathVariable = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        let fileManager = FileManager.default
        for dir in pathVariable.split(separator: ":") {
            let candidate = (String(dir) as NSString).appendingPathComponent(program)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
