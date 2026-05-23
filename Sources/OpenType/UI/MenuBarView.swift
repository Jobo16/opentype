import SwiftUI

struct MenuBarView: View {
    @State private var isRecording = false

    var body: some View {
        Button("开始录音") {
            isRecording.toggle()
        }
        Divider()
        Button("设置…") {
            NSApp.activate(ignoringOtherApps: true)
            if #available(macOS 14.0, *) {
                NSApp.mainMenu?.items.first?.submenu?.item(withTitle: "Settings…")?.performSelector(onMainThread: NSSelectorFromString("_performClick"), with: nil, waitUntilDone: false)
            }
        }
        Divider()
        Button("退出") {
            NSApp.terminate(nil)
        }
    }
}
