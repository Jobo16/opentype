import SwiftUI

/// Main control panel view — the primary app window.
struct MainPanelView: View {
    @ObservedObject var appState: AppState
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Record button + status
            recordSection
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            // History list
            historySection
                .frame(maxHeight: 180)

            Divider()

            // Bottom bar
            bottomBar
        }
        .frame(width: 400)
        .background(.ultraThinMaterial)
    }

    // MARK: - Record Section

    private var recordSection: some View {
        VStack(spacing: 10) {
            // Big record button
            Button {
                appState.toggleRecording()
            } label: {
                ZStack {
                    // Outer pulse ring (visible when recording)
                    Circle()
                        .stroke(appState.phase == .recording ? .red : .clear, lineWidth: 3)
                        .frame(width: 80, height: 80)
                        .scaleEffect(appState.phase == .recording ? 1.3 : 1.0)
                        .opacity(appState.phase == .recording ? 0.3 : 0)
                        .animation(
                            appState.phase == .recording
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .default,
                            value: appState.phase == .recording
                        )

                    // Inner circle
                    Circle()
                        .fill(appState.phase == .recording ? .red : .primary)
                        .frame(width: 60, height: 60)
                        .shadow(color: appState.phase == .recording ? .red.opacity(0.4) : .clear, radius: 12)

                    // Icon
                    if appState.phase == .recording {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(appState.phase == .recording ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: appState.phase == .recording)

            // Status text
            Text(appState.phase.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(appState.phase == .recording ? .red : .primary)

            // Audio level bar
            audioLevelBar
                .frame(width: 200, height: 4)
                .opacity(appState.phase == .recording ? 1 : 0.3)

            // Last result preview
            if !appState.lastTranscript.isEmpty && appState.phase == .idle {
                Text(appState.lastTranscript)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Error message
            if appState.phase == .error && !appState.errorMessage.isEmpty {
                Text(appState.errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var audioLevelBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.1))
                Capsule()
                    .fill(appState.phase == .recording ? .red : .primary.opacity(0.3))
                    .frame(width: geo.size.width * CGFloat(appState.audioLevel))
            }
        }
        .animation(.easeOut(duration: 0.05), value: appState.audioLevel)
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.justify.left")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("暂无识别记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("最近识别")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.history) { item in
                            HistoryRow(item: item)
                            if item.id != appState.history.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                    Text("设置")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text(appState.hotkeyDisplayName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - History Item

struct HistoryItem: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let item: HistoryItem
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.text)
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            VStack(spacing: 4) {
                Text(item.timeString)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Button {
                    copyToClipboard(item.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("复制到剪贴板")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard(item.text)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
