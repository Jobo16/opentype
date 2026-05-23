import SwiftUI

@main
struct OpenTypeApp: App {
    @State private var appState = AppState()

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
        _appState = State(initialValue: {
            let state = AppState()
            state.setup()
            return state
        }())
    }
}
