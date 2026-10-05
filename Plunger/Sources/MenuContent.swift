import AppKit
import Sparkle
import SwiftUI

struct MenuContent: View {
    @Bindable var store: ConfigStore
    let editPanel: EditPanelController
    let updater: SPUUpdater

    var body: some View {
        ForEach(store.config.paths.sortedForDisplay(), id: \.self) { path in
            Menu(displayPath(path)) {
                if store.launchesFoldersInside(path) {
                    FoldersInside(store: store, path: path)
                } else {
                    CommandLauncher(store: store, path: path)
                }
            }
        }

        if !store.config.paths.isEmpty {
            Divider()
        }

        Button("Settings…") { editPanel.show() }

        CheckForUpdatesButton(updater: updater)

        Divider()

        Section("HTTP server") {
            Text(HTTPServer.url(port: store.config.port))
            Text("User: \(Router.username)")
            Button("Copy token") { store.copyToken() }
        }

        Divider()

        Button("Quit Plunger") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct CheckForUpdatesButton: View {
    let updater: SPUUpdater

    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}

private struct FoldersInside: View {
    @Bindable var store: ConfigStore
    let path: String

    var body: some View {
        let folders = PathExpansion.foldersInside(path)
        if folders.isEmpty {
            Text("(no folders inside)")
        } else {
            ForEach(folders, id: \.self) { folder in
                Menu((folder as NSString).lastPathComponent) {
                    CommandLauncher(store: store, path: folder)
                }
            }
        }
    }
}

private struct CommandLauncher: View {
    @Bindable var store: ConfigStore
    let path: String

    var body: some View {
        if store.config.commands.isEmpty && store.config.rawCommands.isEmpty {
            Text("(no saved commands)")
        } else {
            ForEach(store.config.commands.sortedForDisplay(), id: \.self) { command in
                Button(command) {
                    Launcher.launch(path: path, command: command, terminal: store.config.terminal)
                }
            }
            if !store.config.rawCommands.isEmpty {
                Divider()
                ForEach(store.config.rawCommands.sortedForDisplay(), id: \.self) { command in
                    Button(command) {
                        let rendered = Interpolation.render(
                            command,
                            values: ["path": path, "command": command]
                        )
                        Launcher.launchRaw(path: path, command: rendered)
                    }
                }
            }
        }
    }
}

