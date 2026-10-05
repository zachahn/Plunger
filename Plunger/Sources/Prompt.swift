import AppKit

enum Prompt {
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
