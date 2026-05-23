import Cocoa
import Carbon
import os

/// Global hotkey manager using CGEvent tap.
/// Toggle mode: press once to start, press again to stop.
final class HotkeyManager {

    private let logger = Logger(subsystem: "com.opentype.hotkey", category: "Hotkey")

    var onToggle: (() -> Void)?

    // MARK: - Configuration

    struct Binding: Sendable {
        var modifiers: NSEvent.ModifierFlags
        var keyCode: Int
        var isToggle: Bool = true

        var displayName: String {
            var parts: [String] = []
            if modifiers.contains(.command) { parts.append("Cmd") }
            if modifiers.contains(.option) { parts.append("Option") }
            if modifiers.contains(.control) { parts.append("Ctrl") }
            if modifiers.contains(.shift) { parts.append("Shift") }
            parts.append(keyCodeToString(keyCode))
            return parts.joined(separator: "+")
        }

        static func parse(_ string: String) -> Binding? {
            let parts = string.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
            guard !parts.isEmpty else { return nil }

            var modifiers: NSEvent.ModifierFlags = []
            var keyCode: Int?

            for part in parts {
                let lower = part.lowercased()
                switch lower {
                case "cmd", "command": modifiers.insert(.command)
                case "option", "opt", "alt": modifiers.insert(.option)
                case "ctrl", "control": modifiers.insert(.control)
                case "shift": modifiers.insert(.shift)
                default:
                    keyCode = stringToKeyCode(lower)
                }
            }

            guard let key = keyCode else { return nil }
            return Binding(modifiers: modifiers, keyCode: key)
        }
    }

    // MARK: - State

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var isEnabled = false
    private var isRecording = false
    private var maxDurationTimer: Timer?
    private static let maxDuration: TimeInterval = 120

    // Static callback context (CGEvent tap requires a C callback)
    nonisolated(unsafe) static var callbackBinding: Binding?
    nonisolated(unsafe) static var callbackHandler: (() -> Void)?

    // MARK: - Lifecycle

    func enable(binding: Binding) {
        disable()

        guard checkAccess() else {
            logger.warning("Accessibility access not granted")
            return
        }

        Self.callbackBinding = binding
        Self.callbackHandler = { [weak self] in
            self?.handleToggle()
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: nil
        )

        guard let tap else {
            logger.error("Failed to create CGEvent tap")
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.runLoopSource = source
        self.isEnabled = true

        startHealthCheck()
        logger.info("Hotkey enabled: \(binding.displayName)")
    }

    func disable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        tap = nil
        runLoopSource = nil
        healthTimer?.invalidate()
        healthTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        isEnabled = false
        isRecording = false
        Self.callbackBinding = nil
        Self.callbackHandler = nil
        logger.info("Hotkey disabled")
    }

    // MARK: - Event handling

    private func handleToggle() {
        isRecording.toggle()
        if isRecording {
            startMaxDurationTimer()
        } else {
            maxDurationTimer?.invalidate()
            maxDurationTimer = nil
        }
        onToggle?()
    }

    // MARK: - Health check

    private func startHealthCheck() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, let tap = self.tap else { return }
            if !self.isEnabled {
                self.logger.warning("Tap became disabled, re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    private func startMaxDurationTimer() {
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.isRecording {
                self.logger.warning("Max recording duration reached, stopping")
                self.isRecording = false
                self.onToggle?()
            }
        }
    }

    // MARK: - Accessibility check

    private func checkAccess() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - CGEvent tap callback (C function pointer)

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if it gets disabled by the system
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // The health timer will handle re-enabling
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    guard let binding = HotkeyManager.callbackBinding else {
        return Unmanaged.passRetained(event)
    }

    // Match key code
    guard keyCode == binding.keyCode else {
        return Unmanaged.passRetained(event)
    }

    // Match modifiers
    var matched: NSEvent.ModifierFlags = []
    if flags.contains(.maskCommand) { matched.insert(.command) }
    if flags.contains(.maskAlternate) { matched.insert(.option) }
    if flags.contains(.maskControl) { matched.insert(.control) }
    if flags.contains(.maskShift) { matched.insert(.shift) }

    guard matched == binding.modifiers else {
        return Unmanaged.passRetained(event)
    }

    // Swallow the event and trigger callback
    HotkeyManager.callbackHandler?()
    return nil
}

// MARK: - Key code mapping

func keyCodeToString(_ code: Int) -> String {
    switch code {
    case 0x00: return "A"
    case 0x01: return "S"
    case 0x02: return "D"
    case 0x03: return "F"
    case 0x04: return "H"
    case 0x05: return "G"
    case 0x06: return "Z"
    case 0x07: return "X"
    case 0x08: return "C"
    case 0x09: return "V"
    case 0x0B: return "B"
    case 0x0C: return "Q"
    case 0x0D: return "W"
    case 0x0E: return "E"
    case 0x0F: return "R"
    case 0x10: return "Y"
    case 0x11: return "T"
    case 0x12: return "1"
    case 0x13: return "2"
    case 0x14: return "3"
    case 0x15: return "4"
    case 0x17: return "6"
    case 0x16: return "5"
    case 0x1A: return "7"
    case 0x1C: return "8"
    case 0x19: return "9"
    case 0x1D: return "0"
    case 0x24: return "Return"
    case 0x30: return "Tab"
    case 0x31: return "Space"
    case 0x33: return "Delete"
    case 0x35: return "Escape"
    case 0x37: return "Command"
    case 0x38: return "Shift"
    case 0x3A: return "Option"
    case 0x3B: return "Control"
    case 0x3F: return "Fn"
    case 0x41: return ","
    case 0x43: return "."
    case 0x45: return "/"
    case 0x46: return ";"
    case 0x47: return "'"
    case 0x4A: return "-"
    case 0x4B: return "="
    case 0x4E: return "\\"
    default: return "Key(\(code))"
    }
}

func stringToKeyCode(_ string: String) -> Int? {
    let map: [String: Int] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
        "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "5": 0x16, "6": 0x17, "7": 0x1A,
        "8": 0x1C, "9": 0x19, "0": 0x1D,
        "return": 0x24, "enter": 0x24, "tab": 0x30,
        "space": 0x31, "delete": 0x33, "backspace": 0x33,
        "escape": 0x35, "esc": 0x35,
        "fn": 0x3F,
        ",": 0x41, ".": 0x43, "/": 0x45,
        ";": 0x46, "'": 0x47, "-": 0x4A, "=": 0x4B,
        "\\": 0x4E,
    ]
    return map[string.lowercased()]
}
