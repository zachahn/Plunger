import Foundation

enum CommandResolver {
    // Finder-launched GUI apps inherit a minimal PATH that usually lacks Homebrew.
    private static let commonBinDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static func resolveProgram(_ program: String) -> String {
        if program.contains("/") {
            return program
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

    static func programExists(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let program = trimmed.firstIndex(of: " ").map { String(trimmed[..<$0]) } ?? trimmed
        guard program.hasPrefix("/") else { return false }
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        return fileManager.isExecutableFile(atPath: program)
            && fileManager.fileExists(atPath: program, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

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
