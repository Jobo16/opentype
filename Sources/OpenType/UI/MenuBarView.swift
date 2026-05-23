import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button {
            appState.toggleRecording()
        } label: {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
            }
        }
        .keyboardShortcut("r", modifiers: [.command])

        if !appState.lastTranscript.isEmpty {
            Divider()
            Text(appState.lastTranscript)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .leading)
        }

        Divider()

        Button("主窗口") {
            appState.toggleMainWindow()
        }
        .keyboardShortcut("o", modifiers: [.command])

        HStack {
            Text("快捷键")
            Spacer()
            Text(appState.hotkeyDisplayName)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("退出") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private var statusText: String {
        switch appState.phase {
        case .idle: return "开始录音"
        case .recording: return "停止录音"
        case .transcribing: return "识别中…"
        case .optimizing: return "优化中…"
        case .injecting: return "输入中…"
        case .done: return "开始录音"
        case .error: return "开始录音"
        }
    }

    private var statusColor: Color {
        switch appState.phase {
        case .recording: return .red
        case .transcribing, .optimizing, .injecting: return .orange
        case .done: return .green
        case .error: return .red
        case .idle: return .secondary
        }
    }
}
