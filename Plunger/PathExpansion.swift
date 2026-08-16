import Foundation

enum PathExpansion {
    static func childDirectories(of path: String, fileManager: FileManager = .default) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .map { (path as NSString).appendingPathComponent($0) }
            .filter { child in
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: child, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }
            .sortedForDisplay()
    }

    static func launchable(
        paths: [String],
        parents: Set<String>,
        children: (String) -> [String] = { childDirectories(of: $0) }
    ) -> [String] {
        var result: [String] = []
        for path in paths {
            if parents.contains(path) {
                for child in children(path) { result.appendUnique(child) }
            } else {
                result.appendUnique(path)
            }
        }
        return result
    }
}
