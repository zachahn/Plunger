//
//  PlungerApp.swift
//  Plunger
//
//  A menu-bar app that launches Ghostty terminal tabs from saved
//  (path, command) tuples. Ported from the Go menuet app.
//

import SwiftUI

@main
struct PlungerApp: App {
    @State private var store: ConfigStore
    @State private var server: HTTPServer
    @State private var editPanel: EditPanelController

    init() {
        let store = ConfigStore()
        let server = HTTPServer(store: store)
        _store = State(initialValue: store)
        _server = State(initialValue: server)
        _editPanel = State(initialValue: EditPanelController(store: store, server: server))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store, editPanel: editPanel)
        } label: {
            Image(systemName: "wrench.and.screwdriver")
        }
        .onChange(of: scenePhaseStarted, initial: true) { _, _ in
            server.start()
        }
    }

    /// A constant whose `initial` onChange fires once at scene setup, giving a
    /// hook to start the always-on server without an AppDelegate.
    private var scenePhaseStarted: Bool { true }
}
