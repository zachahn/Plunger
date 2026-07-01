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

    /// Shows a one-field dialog for a shell command, with a "Resolve" button that
    /// rewrites the field's program to its absolute path in place. Blocks saving
    /// until the typed command's program exists on disk. Returns nil on cancel.
    @MainActor
    static func command(title: String, info: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = placeholder

        let resolveButton = NSButton(frame: NSRect(x: 208, y: 0, width: 72, height: 24))
        resolveButton.title = "Resolve"
        resolveButton.bezelStyle = .rounded
        let resolveAction = ResolveAction(field: field)
        resolveButton.target = resolveAction
        resolveButton.action = #selector(ResolveAction.resolve(_:))

        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        stack.addSubview(field)
        stack.addSubview(resolveButton)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = field

        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return nil }
            if CommandResolver.programExists(value) { return value }
            let invalid = NSAlert()
            invalid.messageText = "Command not found"
            invalid.informativeText = "\"\(value)\" must be an absolute path to an existing executable. Press Resolve to find it on your PATH."
            invalid.addButton(withTitle: "OK")
            invalid.runModal()
        }
    }

    /// Target/action holder for the Resolve button; NSButton needs an Objective-C
    /// target, which a struct's method can't be. When the typed program matches
    /// more than one executable, a popup menu lets the user pick which one;
    /// otherwise it rewrites the field in place same as before.
    private final class ResolveAction: NSObject {
        let field: NSTextField
        init(field: NSTextField) { self.field = field }

        @objc func resolve(_ sender: NSButton) {
            let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let spaceIndex = trimmed.firstIndex(of: " ")
            let program = spaceIndex.map { String(trimmed[..<$0]) } ?? trimmed
            let rest = spaceIndex.map { String(trimmed[trimmed.index(after: $0)...]) }

            let candidates = CommandResolver.resolveProgramCandidates(program)
            guard candidates.count > 1 else {
                field.stringValue = CommandResolver.resolveCommand(trimmed)
                return
            }

            // A popup NSMenu doesn't track clicks reliably while an NSAlert's
            // modal session is running, so offer the choice via a nested alert
            // (the same pattern the "Command not found" alert already uses)
            // with radio buttons instead.
            guard let chosen = chooseCandidate(candidates) else { return }
            field.stringValue = rest.map { chosen + " " + $0 } ?? chosen
        }

        private func chooseCandidate(_ candidates: [String]) -> String? {
            let alert = NSAlert()
            alert.messageText = "Multiple matches found"
            alert.informativeText = "Choose which one to use."
            alert.addButton(withTitle: "Choose")
            alert.addButton(withTitle: "Cancel")

            let rowHeight: CGFloat = 20
            let stack = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: rowHeight * CGFloat(candidates.count)))
            var buttons: [NSButton] = []
            for (index, candidate) in candidates.enumerated() {
                let y = CGFloat(candidates.count - 1 - index) * rowHeight
                let radio = NSButton(radioButtonWithTitle: candidate, target: self, action: #selector(selectRadio(_:)))
                radio.frame = NSRect(x: 0, y: y, width: 320, height: rowHeight)
                radio.state = index == 0 ? .on : .off
                stack.addSubview(radio)
                buttons.append(radio)
            }
            radioButtons = buttons
            alert.accessoryView = stack

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let selectedIndex = buttons.firstIndex { $0.state == .on } ?? 0
            return candidates[selectedIndex]
        }

        // Plain NSButton radio buttons don't auto-group by superview, so each
        // click must turn off its siblings by hand.
        private var radioButtons: [NSButton] = []
        @objc private func selectRadio(_ sender: NSButton) {
            for button in radioButtons {
                button.state = button === sender ? .on : .off
            }
        }
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
