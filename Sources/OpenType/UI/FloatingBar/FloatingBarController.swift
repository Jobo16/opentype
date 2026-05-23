import AppKit
import SwiftUI

/// Manages a non-activating floating panel that shows during recording.
/// Uses a generation counter to prevent stale hide requests from dismissing a newer show.
final class FloatingBarController {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingBarView>?
    private var generation: UInt64 = 0
    private var hideWorkItem: DispatchWorkItem?

    // MARK: - Show / Hide

    func show(phase: String, audioLevel: Float, transcript: String) {
        generation &+= 1
        hideWorkItem?.cancel()
        hideWorkItem = nil

        let barView = FloatingBarView(
            phase: phase,
            audioLevel: audioLevel,
            transcript: transcript
        )

        if let panel {
            // Update existing panel
            hostingView?.rootView = barView
            panel.orderFront(nil)
            return
        }

        // Create new panel
        let panel = createPanel()
        let hosting = NSHostingView(rootView: barView)
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        panel.contentView!.addSubview(hosting)

        self.panel = panel
        self.hostingView = hosting

        positionPanel(panel)
        panel.orderFront(nil)
    }

    func update(phase: String, audioLevel: Float, transcript: String) {
        guard panel != nil else { return }
        let barView = FloatingBarView(
            phase: phase,
            audioLevel: audioLevel,
            transcript: transcript
        )
        hostingView?.rootView = barView
    }

    func hide(after delay: TimeInterval = 1.0) {
        generation &+= 1
        let currentGen = generation

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGen else { return }
            self.panel?.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hideImmediately() {
        generation &+= 1
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    // MARK: - Panel creation

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 52),
            styleMask: [
                .nonactivatingPanel,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Prevent the panel from becoming key window
        panel.becomesKeyOnlyIfNeeded = true

        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 20
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
