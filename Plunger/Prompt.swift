//
//  Prompt.swift
//  Plunger
//
//  Modal text prompts built on NSAlert, replacing the menuet alert dialogs from
//  the Go app. They run synchronously on the main thread and return the typed
//  values, matching the blocking semantics the menu actions relied on.
//

import AppKit

enum Prompt {
    /// Shows a one-field dialog and returns the trimmed value. A blank entry
    /// returns nil so callers can treat it as a cancel.
    @MainActor
    static func string(title: String, info: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Shows the OS directory picker and returns the chosen directory's path.
    /// Returns nil when the user cancels.
    @MainActor
    static func directory(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    /// Shows a two-field dialog. A blank field keeps the prefilled value, so Edit
    /// can change one field at a time. Returns nil on cancel.
    @MainActor
    static func entry(title: String, info: String, prefill: Entry) -> Entry? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let pathField = NSTextField(frame: NSRect(x: 0, y: 30, width: 280, height: 24))
        pathField.placeholderString = prefill.path.isEmpty ? "Path" : prefill.path
        let commandField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        commandField.placeholderString = prefill.command.isEmpty ? "Command" : prefill.command

        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 54))
        stack.addSubview(pathField)
        stack.addSubview(commandField)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = pathField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        var path = pathField.stringValue
        if path.isEmpty { path = prefill.path }
        var command = commandField.stringValue
        if command.isEmpty { command = prefill.command }
        return Entry(path: path, command: command)
    }

    /// Shows a destructive confirmation. Returns true when the user confirms.
    @MainActor
    static func confirmDelete(message: String, info: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
