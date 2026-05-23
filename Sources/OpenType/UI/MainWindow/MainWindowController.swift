import AppKit
import SwiftUI

/// Manages the main control panel window.
final class MainWindowController {

    private var window: NSWindow?
    private var appState: AppState?
    private var onOpenSettings: (() -> Void)?

    func configure(appState: AppState, onOpenSettings: @escaping () -> Void) {
        self.appState = appState
        self.onOpenSettings = onOpenSettings
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

        let panelView = MainPanelView(appState: appState) { [weak self] in
            self?.onOpenSettings?()
        }

        let hostingView = NSHostingView(rootView: panelView)
        let contentRect = NSRect(x: 0, y: 0, width: 400, height: 420)

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

        // Make window appear in front
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Remember close to hide behavior
        window.delegate = CloseHandler(windowController: self)

        self.window = window
    }
}

/// Intercepts window close to hide instead of destroy.
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
