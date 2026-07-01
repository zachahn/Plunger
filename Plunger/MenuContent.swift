//
//  MenuContent.swift
//  Plunger
//
//  Builds the menu-bar menu tree. The top level lists saved paths; each opens a
//  submenu of saved commands that launch on click. Below are management submenus
//  for the reusable paths and commands lists.
//

import AppKit
import SwiftUI

struct MenuContent: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(store.config.paths, id: \.self) { path in
            Menu(displayPath(path)) {
                CommandLauncher(store: store, path: path)
            }
        }

        if !store.config.paths.isEmpty {
            Divider()
        }

        Menu("Paths") { PathsMenu(store: store) }
        Menu("Commands") { CommandsMenu(store: store) }

        Divider()

        Section("HTTP server") {
            Text(HTTPServer.url)
            Text("User: \(Router.username)")
            Button("Copy token") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(store.token, forType: .string)
            }
        }

        Divider()

        Button("Quit Plunger") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Lists saved commands; clicking one launches the (path, command) tuple.
private struct CommandLauncher: View {
    @Bindable var store: ConfigStore
    let path: String

    var body: some View {
        if store.config.commands.isEmpty {
            Text("(no saved commands)")
        } else {
            ForEach(store.config.commands, id: \.self) { command in
                Button(command) {
                    Launcher.launch(Entry(path: path, command: command))
                }
            }
        }
    }
}

/// Manages the reusable paths list directly.
private struct PathsMenu: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(store.config.paths, id: \.self) { path in
            Menu(displayPath(path)) {
                Button("Delete") { store.deletePath(path) }
            }
        }

        if !store.config.paths.isEmpty {
            Divider()
        }

        Button("Add path…") {
            guard let path = Prompt.directory(
                title: "Choose a working directory to reuse."
            ) else { return }
            store.addPath(path)
        }
    }
}

/// Manages the reusable commands list directly.
private struct CommandsMenu: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(store.config.commands, id: \.self) { command in
            Menu(command) {
                Button("Delete") { store.deleteCommand(command) }
            }
        }

        if !store.config.commands.isEmpty {
            Divider()
        }

        Button("Add command…") {
            guard let command = Prompt.command(
                title: "Add command",
                info: "A command to reuse.",
                placeholder: "Command"
            ) else { return }
            store.addCommand(command)
        }
    }
}
