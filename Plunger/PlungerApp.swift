import Sparkle
import SwiftUI

@main
struct PlungerApp: App {
    @State private var store: ConfigStore
    @State private var server: HTTPServer
    @State private var editPanel: EditPanelController

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        let store = ConfigStore()
        let server = HTTPServer(store: store)
        _store = State(initialValue: store)
        _server = State(initialValue: server)
        _editPanel = State(initialValue: EditPanelController(store: store, server: server))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store, editPanel: editPanel, updater: updaterController.updater)
        } label: {
            menuBarLabel
        }
        .onChange(of: scenePhaseStarted, initial: true) { _, _ in
            server.start()
        }
    }

    /// A constant whose `initial` onChange fires once at scene setup, giving a
    /// hook to start the always-on server without an AppDelegate.
    private var scenePhaseStarted: Bool { true }

    @ViewBuilder
    private var menuBarLabel: some View {
        #if DEBUG
        Image("MenuBarIcon")
            .renderingMode(.original)
        #else
        Image("MenuBarIcon")
        #endif
    }
}
