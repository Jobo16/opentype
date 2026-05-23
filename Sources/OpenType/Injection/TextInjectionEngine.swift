import AppKit

/// Copies text to the clipboard, simulates Cmd+V, then restores the previous clipboard.
struct TextInjectionEngine {

    func inject(_ text: String) async throws {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents.
        let savedTypes = pasteboard.types ?? []
        var savedData: [NSPasteboard.PasteboardType: Data] = [:]
        for type in savedTypes {
            savedData[type] = pasteboard.data(forType: type)
        }

        // Set the text.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V via CGEvent.
        try await simulatePaste()

        // Restore clipboard after a short delay (apps need time to read).
        try await Task.sleep(nanoseconds: 300_000_000)
        pasteboard.clearContents()
        for (type, data) in savedData {
            pasteboard.setData(data, forType: type)
        }
    }

    private func simulatePaste() async throws {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)   // v
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
