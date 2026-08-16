import Foundation

enum PathExpansion {
    static func foldersInside(_ path: String, fileManager: FileManager = .default) -> [String] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .map { (path as NSString).appendingPathComponent($0) }
            .filter { folder in
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: folder, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }
            .sortedForDisplay()
    }

    static func launchable(
        paths: [String],
        launchFoldersInside: Set<String>,
        folders: (String) -> [String] = { foldersInside($0) }
    ) -> [String] {
        var result: [String] = []
        for path in paths {
            if launchFoldersInside.contains(path) {
                for folder in folders(path) { result.appendUnique(folder) }
            } else {
                result.appendUnique(path)
            }
        }
        return result
    }
}
