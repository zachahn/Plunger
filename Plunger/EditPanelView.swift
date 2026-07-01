//
//  EditPanelView.swift
//  Plunger
//
//  The persistent edit panel's content (see FloatingPanel.swift): a split list
//  of saved paths and commands, replacing the old NSAlert-based PathsMenu and
//  CommandsMenu add/delete flows from MenuContent.swift.
//

import SwiftUI

struct EditPanelView: View {
    @Bindable var store: ConfigStore

    var body: some View {
        HSplitView {
            PathsColumn(store: store)
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
            CommandsColumn(store: store)
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct PathsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paths").font(.headline).padding([.top, .horizontal])

            List(store.config.paths, id: \.self) { path in
                HStack {
                    Text(displayPath(path))
                    Spacer()
                    Button("Delete", role: .destructive) { pendingDelete = path }
                        .buttonStyle(.borderless)
                }
                .contentShape(Rectangle())
                .onTapGesture { edit(path) }
            }

            Button("Add path…") {
                guard let path = Prompt.directory(
                    title: "Choose a working directory to reuse."
                ) else { return }
                store.addPath(path)
            }
            .padding()
        }
        .alert(
            "Delete path?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { path in
            Button("Delete", role: .destructive) { store.deletePath(path) }
            Button("Cancel", role: .cancel) {}
        } message: { path in
            Text(displayPath(path))
        }
    }

    private func edit(_ path: String) {
        guard let newPath = Prompt.directory(
            title: "Choose a working directory to reuse.",
            initialDirectory: path
        ) else { return }
        store.updatePath(path, to: newPath)
    }
}

private struct CommandsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?
    @State private var editingCommand: String?
    @State private var fieldValue = ""
    @State private var notFoundAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Commands").font(.headline).padding([.top, .horizontal])

            List(store.config.commands, id: \.self) { command in
                if editingCommand == command {
                    editorRow
                } else {
                    HStack {
                        Text(command)
                        Spacer()
                        Button("Delete", role: .destructive) { pendingDelete = command }
                            .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing(command) }
                }
            }

            if editingCommand == "" {
                editorRow.padding()
            } else {
                Button("Add command…") { beginEditing("") }
                    .padding()
            }
        }
        .alert(
            "Delete command?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { command in
            Button("Delete", role: .destructive) { store.deleteCommand(command) }
            Button("Cancel", role: .cancel) {}
        } message: { command in
            Text(command)
        }
        .alert("Command not found", isPresented: $notFoundAlert) {
            Button("OK") {}
        } message: {
            Text("\"\(fieldValue)\" must be an absolute path to an existing executable. Press Resolve to find it on your PATH.")
        }
    }

    private var editorRow: some View {
        HStack {
            TextField("Command", text: $fieldValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button("Resolve") { fieldValue = CommandResolver.resolveCommand(fieldValue) }
            Button("Save", action: save)
            Button("Cancel") { editingCommand = nil }
        }
    }

    private func beginEditing(_ command: String) {
        fieldValue = command
        editingCommand = command
    }

    private func save() {
        let trimmed = fieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard CommandResolver.programExists(trimmed) else {
            notFoundAlert = true
            return
        }
        if let editingCommand, !editingCommand.isEmpty {
            store.updateCommand(editingCommand, to: trimmed)
        } else {
            store.addCommand(trimmed)
        }
        editingCommand = nil
        fieldValue = ""
    }
}
