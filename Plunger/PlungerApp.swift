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

    init() {
        let store = ConfigStore()
        _store = State(initialValue: store)
        _server = State(initialValue: HTTPServer(store: store))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
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
