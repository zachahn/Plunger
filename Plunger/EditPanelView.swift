//
//  EditPanelView.swift
//  Plunger
//
//  The persistent edit panel's content (see FloatingPanel.swift): two Tables
//  of saved paths and commands. Each row has icon-only edit/delete actions
//  (rather than reusing Table's row-click selection, which read as
//  accidental) that open a popover anchored to the row with a small form
//  instead of a blocking NSAlert.
//

import SwiftUI

/// Table requires Identifiable rows; the saved paths/commands are plain,
/// deduplicated strings, so this wraps a value just enough to satisfy that
/// without adding a project-wide Identifiable conformance to String itself.
private struct Row: Identifiable, Hashable {
    let value: String
    var id: String { value }
}

struct EditPanelView: View {
    @Bindable var store: ConfigStore

    var body: some View {
        HSplitView {
            PathsColumn(store: store)
                .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
            CommandsColumn(store: store)
                .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

/// The pencil/trash row-action buttons shared by both columns.
private struct RowActions: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .help("Edit")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

private struct PathsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?
    @State private var editingPath: String?
    @State private var isAddingPath = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Paths").font(.headline).padding([.top, .horizontal])

            Table(of: Row.self) {
                TableColumn("Path") { row in
                    Text(displayPath(row.value))
                }
                TableColumn("Actions") { row in
                    RowActions(
                        onEdit: { editingPath = row.value },
                        onDelete: { pendingDelete = row.value }
                    )
                }
                .width(70)
            } rows: {
                ForEach(store.config.paths, id: \.self) { path in
                    TableRow(Row(value: path))
                }
            }

            HStack {
                Button("Add path…") { isAddingPath = true }
                    .popover(isPresented: $isAddingPath) {
                        PathPopover(title: "New Path") { newPath in
                            store.addPath(newPath)
                        }
                    }
            }
            .padding()
        }
        .popover(isPresented: Binding(get: { editingPath != nil }, set: { if !$0 { editingPath = nil } })) {
            if let path = editingPath {
                PathPopover(title: "Edit Path", initialPath: path) { newPath in
                    store.updatePath(path, to: newPath)
                }
            }
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
}

/// A small non-modal form for choosing a directory, shown in a popover. The
/// directory picker itself is still the native NSOpenPanel; this just wraps
/// the trigger and shows the chosen value before committing.
private struct PathPopover: View {
    let title: String
    var initialPath: String = ""
    let onSave: (String) -> Void

    @State private var path: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialPath: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.initialPath = initialPath
        self.onSave = onSave
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            LabeledContent("Directory") {
                Button(path.isEmpty ? "Choose…" : displayPath(path)) {
                    guard let chosen = Prompt.directory(
                        title: "Choose a working directory to reuse.",
                        initialDirectory: path.isEmpty ? nil : path
                    ) else { return }
                    path = chosen
                }
                .lineLimit(1)
                .truncationMode(.head)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(path)
                    dismiss()
                }
                .disabled(path.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CommandsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?
    @State private var editingCommand: String?
    @State private var isAddingCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Commands").font(.headline).padding([.top, .horizontal])

            Table(of: Row.self) {
                TableColumn("Command") { row in
                    Text(row.value)
                }
                TableColumn("Actions") { row in
                    RowActions(
                        onEdit: { editingCommand = row.value },
                        onDelete: { pendingDelete = row.value }
                    )
                }
                .width(70)
            } rows: {
                ForEach(store.config.commands, id: \.self) { command in
                    TableRow(Row(value: command))
                }
            }

            HStack {
                Button("Add command…") { isAddingCommand = true }
                    .popover(isPresented: $isAddingCommand) {
                        CommandPopover(title: "New Command") { newCommand in
                            store.addCommand(newCommand)
                        }
                    }
            }
            .padding()
        }
        .popover(isPresented: Binding(get: { editingCommand != nil }, set: { if !$0 { editingCommand = nil } })) {
            if let command = editingCommand {
                CommandPopover(title: "Edit Command", initialCommand: command) { newCommand in
                    store.updateCommand(command, to: newCommand)
                }
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
    }
}

/// A small non-modal form for typing and resolving a command, shown in a
/// popover. Carries the same validation as the old NSAlert-based dialog:
/// Resolve rewrites the program to an absolute path; Save is blocked until
/// the program exists on disk.
private struct CommandPopover: View {
    let title: String
    var initialCommand: String = ""
    let onSave: (String) -> Void

    @State private var command: String
    @State private var notFoundAlert = false
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialCommand: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.initialCommand = initialCommand
        self.onSave = onSave
        _command = State(initialValue: initialCommand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Button("Resolve") { command = CommandResolver.resolveCommand(command) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Command not found", isPresented: $notFoundAlert) {
            Button("OK") {}
        } message: {
            Text("\"\(command)\" must be an absolute path to an existing executable. Press Resolve to find it on your PATH.")
        }
    }

    private func save() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard CommandResolver.programExists(trimmed) else {
            notFoundAlert = true
            return
        }
        onSave(trimmed)
        dismiss()
    }
}
