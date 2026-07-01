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
    @State private var store = ConfigStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Image(systemName: "wrench.and.screwdriver")
        }
    }
}
