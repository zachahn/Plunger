//
//  MenuContent.swift
//  Plunger
//
//  Builds the menu-bar menu tree. The top level lists saved paths; each opens a
//  submenu of saved commands that launch on click. Below are management submenus
//  for the reusable paths and commands lists.
//

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
                CommandLauncher(store: store, path: path)
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

/// A "Check for Updates…" button that tracks Sparkle's `canCheckForUpdates`,
/// so it dims while a check is already running or the updater is unavailable.
private struct CheckForUpdatesButton: View {
    let updater: SPUUpdater

    @State private var canCheck = false

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!canCheck)
            .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}

/// Lists saved commands; clicking one launches the (path, command) pair.
private struct CommandLauncher: View {
    @Bindable var store: ConfigStore
    let path: String

    var body: some View {
        if store.config.commands.isEmpty {
            Text("(no saved commands)")
        } else {
            ForEach(store.config.commands.sortedForDisplay(), id: \.self) { command in
                Button(command) {
                    Launcher.launch(path: path, command: command)
                }
            }
        }
    }
}

