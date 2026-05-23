import AppKit
import SwiftUI

/// A macOS-style hotkey capture field: click to record, press keys, displays the combination.
struct HotKeyField: NSViewRepresentable {
    @Binding var hotkeyString: String
    var onChange: ((String) -> Void)?

    func makeNSView(context: Context) -> HotKeyFieldNSView {
        let view = HotKeyFieldNSView()
        view.hotkeyString = hotkeyString
        view.onHotkeyChanged = { newString in
            hotkeyString = newString
            onChange?(newString)
        }
        return view
    }

    func updateNSView(_ nsView: HotKeyFieldNSView, context: Context) {
        nsView.hotkeyString = hotkeyString
    }
}

final class HotKeyFieldNSView: NSView {

    var hotkeyString: String = "" {
        didSet { updateLabel() }
    }
    var onHotkeyChanged: ((String) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let instructionLabel = NSTextField(labelWithString: "按下快捷键")
    private var isRecording = false
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Key label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        addSubview(label)

        // Instruction (shown when recording)
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.font = .systemFont(ofSize: 12, weight: .regular)
        instructionLabel.textColor = .secondaryLabelColor
        instructionLabel.alignment = .center
        instructionLabel.isHidden = true
        addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            instructionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            instructionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        updateLabel()

        // Click to start recording
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(clicked))
        addGestureRecognizer(clickGesture)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 28)
    }

    @objc private func clicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        label.isHidden = true
        instructionLabel.isHidden = false
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2

        // Monitor keyboard events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handleKeyEvent(event)
            return nil  // consume the event
        }
    }

    private func stopRecording() {
        isRecording = false
        instructionLabel.isHidden = true
        label.isHidden = false
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Only accept keyDown with at least one modifier
        guard event.type == .keyDown else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Require at least one modifier key (Cmd, Option, Ctrl, Shift)
        // Fn alone is also allowed
        let hasModifier = flags.contains(.command) || flags.contains(.option)
            || flags.contains(.control) || flags.contains(.shift) || flags.contains(.function)

        // Single Escape = cancel
        if event.keyCode == 0x35 && flags.isEmpty {
            stopRecording()
            return
        }

        // Single modifier-only key (Cmd, Option, etc.) = ignore, wait for combo
        let onlyModifier = flags.subtracting([.function]) == flags
        if onlyModifier && !hasModifier {
            return
        }

        // Build the hotkey string
        var parts: [String] = []
        if flags.contains(.command) { parts.append("Cmd") }
        if flags.contains(.option) { parts.append("Option") }
        if flags.contains(.control) { parts.append("Ctrl") }
        if flags.contains(.shift) { parts.append("Shift") }
        parts.append(keyCodeToString(Int(event.keyCode)))

        let result = parts.joined(separator: "+")
        hotkeyString = result
        onHotkeyChanged?(result)
        stopRecording()
    }

    private func updateLabel() {
        if hotkeyString.isEmpty {
            label.stringValue = "点击设置快捷键"
            label.textColor = .placeholderTextColor
        } else {
            label.stringValue = hotkeyString
            label.textColor = .labelColor
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
