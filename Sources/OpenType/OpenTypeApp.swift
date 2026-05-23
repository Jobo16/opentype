import SwiftUI

@main
struct OpenTypeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Settings {
            SettingsView()
        }

        MenuBarExtra("OpenType", systemImage: "waveform") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.menu)
        .defaultAppStorage(UserDefaults.standard)
    }

    init() {
        _appState = StateObject(wrappedValue: {
            let state = AppState()
            state.setup()
            return state
        }())
    }
}
