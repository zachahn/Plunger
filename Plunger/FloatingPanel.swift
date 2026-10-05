import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        title = "Plunger Settings"

        // setFrameAutosaveName only restores a frame once one has been saved
        // (e.g. after the user drags the panel), so the initial position is
        // set explicitly here, anchored to the top-right of the screen that
        // holds the menu bar.
        if !setFrameUsingName("EditPanel") {
            positionTopRight(contentRect: contentRect)
        }
        setFrameAutosaveName("EditPanel")
    }

    private func positionTopRight(contentRect: NSRect) {
        guard let screen = NSScreen.main else { return }
        let inset: CGFloat = 16
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - contentRect.width - inset,
            y: screen.visibleFrame.maxY - contentRect.height - inset
        )
        setFrameOrigin(origin)
    }

    // A nonactivating panel still needs to accept key status itself, or its
    // text fields and buttons won't respond to clicks/typing.
    override var canBecomeKey: Bool { true }
}

@MainActor
final class EditPanelController {
    private var panel: FloatingPanel?
    private let store: ConfigStore
    private let server: HTTPServer

    init(store: ConfigStore, server: HTTPServer) {
        self.store = store
        self.server = server
    }

    func toggle() {
        if let panel, panel.isVisible {
            panel.close()
        } else {
            show()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440))
        panel.contentView = NSHostingView(rootView: EditPanelView(store: store, server: server))
        return panel
    }
}
