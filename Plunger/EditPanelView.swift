import SwiftUI

private struct Row: Identifiable, Hashable {
    let value: String
    var id: String { value }
}

private extension Array where Element == String {
    func asRows() -> [Row] {
        map { Row(value: $0) }
    }
}

struct EditPanelView: View {
    @Bindable var store: ConfigStore
    let server: HTTPServer

    var body: some View {
        TabView {
            PathsColumn(store: store)
                .tabItem { Label("Paths", systemImage: "folder") }
            CommandsColumn(store: store)
                .tabItem { Label("Commands", systemImage: "terminal") }
            RawCommandsColumn(store: store)
                .tabItem { Label("Raw", systemImage: "chevron.left.forwardslash.chevron.right") }
            HTTPServerColumn(store: store, server: server)
                .tabItem { Label("HTTP Server", systemImage: "network") }
        }
        .padding(.top, 8)
        .frame(minWidth: 360, minHeight: 420)
    }
}

private struct HTTPServerColumn: View {
    @Bindable var store: ConfigStore
    @Bindable var server: HTTPServer
    @State private var confirmRegenerate = false
    @State private var portText = ""

    private var parsedPort: UInt16? {
        guard let value = UInt16(portText.trimmingCharacters(in: .whitespaces)), value > 0 else {
            return nil
        }
        return value
    }

    var body: some View {
        Form {
            LabeledContent("URL") {
                Text(HTTPServer.url(port: store.config.boundPort)).textSelection(.enabled)
            }
            LabeledContent("Username") {
                Text(Router.username).textSelection(.enabled)
            }
            LabeledContent("Port") {
                HStack {
                    TextField("", text: $portText)
                        .frame(width: 80)
                        .onSubmit(applyPort)
                    Button("Apply", action: applyPort)
                        .disabled(parsedPort == nil || parsedPort == store.config.port)
                }
            }
            if case .failed(let port) = server.status {
                Label(
                    "Could not bind port \(String(port)). It may be in use by another app — try a different port.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
                .font(.callout)
            }
            Toggle("Require token", isOn: Binding(
                get: { store.config.authEnabled },
                set: { store.setAuthEnabled($0) }
            ))
            if !store.config.authEnabled {
                Label(
                    "Anyone who can reach this port can launch commands without the token.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.callout)
            }

            LabeledContent("Token") {
                VStack(alignment: .trailing, spacing: 8) {
                    Text(store.token)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack {
                        Button("Copy") { store.copyToken() }
                        Button("Regenerate…") { confirmRegenerate = true }
                    }
                }
            }

            Section("Allowed networks") {
                ForEach(PeerCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.label)
                            Text(category.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // "Any" subsumes the others: while it's on, show them as
                    // checked and locked. The stored set is untouched, so
                    // clearing "Any" restores whatever was selected before.
                    .disabled(category != .any && store.config.allowedPeers.contains(.any))
                }
                if store.config.allowedPeers.contains(.any) {
                    Label(
                        "Any host that can reach this port is allowed to connect.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
                if store.config.allowedPeers.isEmpty {
                    Label(
                        "No networks are allowed — the server will refuse every connection.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { portText = String(store.config.port) }
        .alert("Regenerate token?", isPresented: $confirmRegenerate) {
            Button("Regenerate", role: .destructive) { store.regenerateToken() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Any client still using the current token will stop working until it picks up the new one.")
        }
    }

    private func binding(for category: PeerCategory) -> Binding<Bool> {
        Binding(
            get: {
                if category != .any && store.config.allowedPeers.contains(.any) { return true }
                return store.config.allowedPeers.contains(category)
            },
            set: { isOn in
                var peers = store.config.allowedPeers
                if isOn { peers.insert(category) } else { peers.remove(category) }
                store.setAllowedPeers(peers)
            }
        )
    }

    private func applyPort() {
        guard let port = parsedPort, port != store.config.port else { return }
        store.setPort(port)
        server.restart()
        portText = String(store.config.port)
    }
}

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
                TableColumn("Launches") { row in
                    Text(store.launchesFoldersInside(row.value) ? "Folders inside" : "This folder")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 100, ideal: 110)
            } rows: {
                ForEach(store.config.paths.sortedForDisplay().asRows()) { row in
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
                PathForm(title: "New Path") { store.addPath($0, launchFoldersInside: $1) }
            case .edit(let value):
                PathForm(
                    title: "Edit Path",
                    initialPath: value,
                    initialLaunchFoldersInside: store.launchesFoldersInside(value)
                ) { store.updatePath(value, to: $0, launchFoldersInside: $1) }
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

private struct PathForm: View {
    let title: String
    var initialPath: String = ""
    var initialLaunchFoldersInside: Bool = false
    let onSave: (String, Bool) -> Void

    @State private var path: String
    @State private var launchFoldersInside: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialPath: String = "",
        initialLaunchFoldersInside: Bool = false,
        onSave: @escaping (String, Bool) -> Void
    ) {
        self.title = title
        self.initialPath = initialPath
        self.initialLaunchFoldersInside = initialLaunchFoldersInside
        self.onSave = onSave
        _path = State(initialValue: initialPath)
        _launchFoldersInside = State(initialValue: initialLaunchFoldersInside)
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

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch folders inside", isOn: $launchFoldersInside)
                Text("Offer each folder inside this directory instead of the directory itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(path, launchFoldersInside)
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
        VStack(spacing: 0) {
            HStack {
                Picker("Terminal", selection: Binding(
                    get: { store.config.terminal },
                    set: { store.setTerminal($0) }
                )) {
                    ForEach(Terminal.allCases) { terminal in
                        Text(terminal.label).tag(terminal)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Which terminal app a saved command opens in. Raw commands ignore this and run directly.")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Divider()

            TabColumn {
                Table(of: Row.self, selection: $selection) {
                    TableColumn("Command") { row in
                        Text(row.value)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } rows: {
                    ForEach(store.config.commands.sortedForDisplay().asRows()) { row in
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

private struct RawCommandsColumn: View {
    @Bindable var store: ConfigStore
    @State private var pendingDelete: String?
    @State private var sheet: RawCommandSheet?
    @State private var selection: Row.ID?

    private enum RawCommandSheet: Identifiable {
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
                TableColumn("Raw Command") { row in
                    Text(row.value)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } rows: {
                ForEach(store.config.rawCommands.sortedForDisplay().asRows()) { row in
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
                RawCommandForm(title: "New Raw Command") { store.addRawCommand($0) }
            case .edit(let value):
                RawCommandForm(title: "Edit Raw Command", initialCommand: value) {
                    store.updateRawCommand(value, to: $0)
                }
            }
        }
        .alert(
            "Delete raw command?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { command in
            Button("Delete", role: .destructive) { store.deleteRawCommand(command) }
            Button("Cancel", role: .cancel) {}
        } message: { command in
            Text(command)
        }
    }
}

private struct RawCommandForm: View {
    let title: String
    var initialCommand: String = ""
    let onSave: (String) -> Void

    @State private var command: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialCommand: String = "", onSave: @escaping (String) -> Void) {
        self.title = title
        self.initialCommand = initialCommand
        self.onSave = onSave
        _command = State(initialValue: initialCommand)
    }

    private var trimmed: String {
        command.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)

            TextField("Raw Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Text("Runs directly, no terminal. Use {{path}} and {{command}} as placeholders.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .disabled(trimmed.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
