import SwiftUI

@main
struct OpenTypeApp: App {
    var body: some Scene {
        Settings {
            SettingsView()
        }

        MenuBarExtra("OpenType", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
