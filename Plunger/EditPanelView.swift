//
//  EditPanelView.swift
//  Plunger
//
//  The persistent edit panel's content (see FloatingPanel.swift): a TabView
//  with one full-width Table per tab (Paths, Commands). Click selects a row;
//  double-click or the right-click menu edits it (in a sheet); Delete key or
//  the − button removes it. A +/− bar under each table handles add/remove,
//  since SwiftUI's Table has no built-in one. Rows are sorted alphabetically
//  for display; the stored order in ConfigStore is left untouched.
//

import SwiftUI

/// Table requires Identifiable rows; the saved paths/commands are plain,
/// deduplicated strings, so this wraps a value just enough to satisfy that
/// without adding a project-wide Identifiable conformance to String itself.
private struct Row: Identifiable, Hashable {
    let value: String
    var id: String { value }
}

private extension Array where Element == String {
    /// Wraps each string as a Row, sorted case-insensitively for display. The
    /// stored order in ConfigStore is left untouched; this is presentation only.
    func sortedForDisplay() -> [Row] {
        sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { Row(value: $0) }
    }
}

struct EditPanelView: View {
    @Bindable var store: ConfigStore

    var body: some View {
        TabView {
            PathsColumn(store: store)
                .tabItem { Label("Paths", systemImage: "folder") }
            CommandsColumn(store: store)
                .tabItem { Label("Commands", systemImage: "terminal") }
        }
        .padding(.top, 8)
        .frame(minWidth: 360, minHeight: 420)
    }
}

/// Wraps a table and a +/− toolbar footer, shared by both tabs so they lay
/// out the same. The tab label supplies the heading, so no title here.
private struct TabColumn<Content: View, Footer: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            content

            Divider()

            HStack(spacing: 0) {
                footer
                Spacer()
            }
            .frame(height: 24)
            .padding(.horizontal, 4)
        }
    }
}

/// The macOS-style +/− button pair that sits under a Table. SwiftUI's Table
/// has no built-in add/remove control, so this hand-builds the AppKit look:
/// two small borderless buttons in the table's footer strip. The − button is
/// disabled until a row is selected.
private struct PlusMinusBar: View {
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .help("Add")

            Button(action: onRemove) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .help("Remove")
            .disabled(!canRemove)
        }
        .buttonStyle(.borderless)
    }
}

private struct PathsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?
    @State private var sheet: PathSheet?
    @State private var selection: Row.ID?

    /// The add/edit form shown in a sheet. `edit` carries the row being edited.
    private enum PathSheet: Identifiable {
        case add
        case edit(String)

        var id: String {
            switch self {
            case .add: ""
            case .edit(let value): value
            }
        }
    }

    var body: some View {
        TabColumn {
            Table(of: Row.self, selection: $selection) {
                TableColumn("Path") { row in
                    Text(displayPath(row.value))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            } rows: {
                ForEach(store.config.paths.sortedForDisplay()) { row in
                    TableRow(row)
                }
            }
            .contextMenu(forSelectionType: Row.ID.self) { ids in
                if let value = ids.first {
                    Button("Edit…") { sheet = .edit(value) }
                    Button("Delete", role: .destructive) { pendingDelete = value }
                }
            } primaryAction: { ids in
                if let value = ids.first { sheet = .edit(value) }
            }
            .onDeleteCommand { if let value = selection { pendingDelete = value } }
        } footer: {
            PlusMinusBar(
                canRemove: selection != nil,
                onAdd: { sheet = .add },
                onRemove: { if let value = selection { pendingDelete = value } }
            )
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                PathForm(title: "New Path") { store.addPath($0) }
            case .edit(let value):
                PathForm(title: "Edit Path", initialPath: value) { store.updatePath(value, to: $0) }
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

/// A small form for choosing a directory, shown in a sheet. The directory
/// picker itself is still the native NSOpenPanel; this just wraps the trigger
/// and shows the chosen value before committing.
private struct PathForm: View {
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
        VStack(alignment: .leading, spacing: 16) {
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
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(path)
                    dismiss()
                }
                .disabled(path.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

private struct CommandsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?
    @State private var sheet: CommandSheet?
    @State private var selection: Row.ID?

    /// The add/edit form shown in a sheet. `edit` carries the row being edited.
    private enum CommandSheet: Identifiable {
        case add
        case edit(String)

        var id: String {
            switch self {
            case .add: ""
            case .edit(let value): value
            }
        }
    }

    var body: some View {
        TabColumn {
            Table(of: Row.self, selection: $selection) {
                TableColumn("Command") { row in
                    Text(row.value)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } rows: {
                ForEach(store.config.commands.sortedForDisplay()) { row in
                    TableRow(row)
                }
            }
            .contextMenu(forSelectionType: Row.ID.self) { ids in
                if let value = ids.first {
                    Button("Edit…") { sheet = .edit(value) }
                    Button("Delete", role: .destructive) { pendingDelete = value }
                }
            } primaryAction: { ids in
                if let value = ids.first { sheet = .edit(value) }
            }
            .onDeleteCommand { if let value = selection { pendingDelete = value } }
        } footer: {
            PlusMinusBar(
                canRemove: selection != nil,
                onAdd: { sheet = .add },
                onRemove: { if let value = selection { pendingDelete = value } }
            )
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                CommandForm(title: "New Command") { store.addCommand($0) }
            case .edit(let value):
                CommandForm(title: "Edit Command", initialCommand: value) { store.updateCommand(value, to: $0) }
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

/// A small form for typing and resolving a command, shown in a sheet. Carries
/// the same validation as the old NSAlert-based dialog: Resolve rewrites the
/// program to an absolute path; Save is blocked until the program exists on
/// disk.
private struct CommandForm: View {
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
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)

            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Button("Resolve") { command = CommandResolver.resolveCommand(command) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
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
