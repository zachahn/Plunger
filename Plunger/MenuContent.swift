//
//  MenuContent.swift
//  Plunger
//
//  Builds the menu-bar menu tree. Ported from the Go app's menuItems and its
//  submenu builders. The top level lists saved entries that launch on click,
//  then management submenus for entries and the reusable pick-lists.
//

import AppKit
import SwiftUI

struct MenuContent: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(Array(store.config.entries.enumerated()), id: \.element.id) { _, entry in
            Button(entry.label) { Launcher.launch(entry) }
        }

        if !store.config.entries.isEmpty {
            Divider()
        }

        Menu("New") { NewMenu(store: store) }
        Menu("Edit") { EditMenu(store: store) }
        Menu("Delete") { DeleteMenu(store: store) }

        Divider()

        Menu("Paths") { PathsMenu(store: store) }
        Menu("Commands") { CommandsMenu(store: store) }

        Divider()

        Button("Quit Plunger") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// The "New" tree: pick a saved path, then a saved command, to create a tuple —
/// plus a typed fallback for values not yet in the lists.
private struct NewMenu: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(store.config.paths, id: \.self) { path in
            Menu(path) {
                CommandPicker(store: store, path: path)
            }
        }

        if !store.config.paths.isEmpty {
            Divider()
        }

        Button("Type new…") {
            guard let entry = Prompt.entry(
                title: "New",
                info: "Set the path and command to run.",
                prefill: Entry(path: "", command: "")
            ) else { return }
            store.addEntry(entry)
        }
    }
}

/// Lists saved commands; clicking one creates the (path, command) tuple.
private struct CommandPicker: View {
    @Bindable var store: ConfigStore
    let path: String

    var body: some View {
        if store.config.commands.isEmpty {
            Text("(no saved commands)")
        } else {
            ForEach(store.config.commands, id: \.self) { command in
                Button(command) {
                    store.addEntry(Entry(path: path, command: command))
                }
            }
        }
    }
}

/// Lists saved tuples; clicking one opens the edit dialog.
private struct EditMenu: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(Array(store.config.entries.enumerated()), id: \.element.id) { index, entry in
            Button(entry.label) {
                guard let edited = Prompt.entry(
                    title: "Edit",
                    info: "Leave a field blank to keep its current value.",
                    prefill: entry
                ) else { return }
                store.updateEntry(at: index, with: edited)
            }
        }
    }
}

/// Lists saved tuples; clicking one confirms and deletes it.
private struct DeleteMenu: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(Array(store.config.entries.enumerated()), id: \.element.id) { index, entry in
            Button(entry.label) {
                guard Prompt.confirmDelete(
                    message: "Delete entry?",
                    info: entry.label
                ) else { return }
                store.deleteEntry(at: index)
            }
        }
    }
}

/// Manages the reusable paths list directly.
private struct PathsMenu: View {
    @Bindable var store: ConfigStore

    var body: some View {
        ForEach(store.config.paths, id: \.self) { path in
            Menu(path) {
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
            guard let command = Prompt.string(
                title: "Add command",
                info: "A command to reuse.",
                placeholder: "Command"
            ) else { return }
            store.addCommand(command)
        }
    }
}
