import AppKit
import SwiftUI

/// Manages the main control panel window.
final class MainWindowController {

    private var window: NSWindow?
    private var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        createWindow()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        guard let appState else { return }

        let panelView = MainPanelView(appState: appState)
        let hostingView = NSHostingView(rootView: panelView)
        let contentRect = NSRect(x: 0, y: 0, width: 420, height: 480)

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "OpenType"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.delegate = CloseHandler(windowController: self)

        self.window = window
    }
}

private final class CloseHandler: NSObject, NSWindowDelegate {
    weak var windowController: MainWindowController?

    init(windowController: MainWindowController) {
        self.windowController = windowController
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
