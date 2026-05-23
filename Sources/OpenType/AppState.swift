import Foundation
import Combine
import os
import AppKit

/// Central app state coordinator. Owns the recognition session and hotkey manager.
@MainActor
final class AppState: ObservableObject {

    private let logger = Logger(subsystem: "com.opentype.app", category: "AppState")

    // MARK: - Published state

    enum Phase: String, Sendable {
        case idle
        case recording
        case transcribing
        case optimizing
        case injecting
        case done
        case error

        var label: String {
            switch self {
            case .idle: return "就绪"
            case .recording: return "录音中…"
            case .transcribing: return "识别中…"
            case .optimizing: return "优化中…"
            case .injecting: return "输入中…"
            case .done: return "完成"
            case .error: return "出错"
            }
        }
    }

    @Published var phase: Phase = .idle {
        didSet { updateFloatingBar() }
    }
    @Published var audioLevel: Float = 0 {
        didSet { updateFloatingBarLevel() }
    }
    @Published var lastTranscript: String = ""
    @Published var errorMessage: String = ""
    @Published var hotkeyDisplayName: String = "Option+Space"
    @Published var history: [HistoryItem] = []

    // MARK: - Dependencies

    private let session = RecognitionSession()
    private let hotkeyManager = HotkeyManager()
    private let floatingBar = FloatingBarController()
    let mainWindow = MainWindowController()
    private var phaseTask: Task<Void, Never>?

    // MARK: - Init

    func setup() {
        loadHotkey()
        setupHotkeyCallback()
        setupAudioLevelForwarding()
        mainWindow.configure(appState: self) { [weak self] in
            self?.openSettings()
        }
        // Show main window after a short delay to let the app fully initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainWindow()
        }
    }

    // MARK: - Main Window

    func toggleMainWindow() {
        mainWindow.toggle()
    }

    func showMainWindow() {
        mainWindow.show()
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    // MARK: - Hotkey

    private func loadHotkey() {
        let raw = CredentialService.hotkeyString
        hotkeyDisplayName = HotkeyManager.Binding.parse(raw)?.displayName ?? raw
    }

    private func setupHotkeyCallback() {
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleRecording()
            }
        }
        enableHotkey()
    }

    func enableHotkey() {
        let raw = CredentialService.hotkeyString
        guard let binding = HotkeyManager.Binding.parse(raw) else {
            logger.error("Invalid hotkey string: \(raw)")
            return
        }
        hotkeyManager.enable(binding: binding)
        hotkeyDisplayName = binding.displayName
    }

    func updateHotkey(_ string: String) {
        CredentialService.hotkeyString = string
        enableHotkey()
    }

    // MARK: - Recording actions

    func toggleRecording() {
        switch phase {
        case .idle, .done, .error:
            startRecording()
        case .recording, .transcribing, .optimizing, .injecting:
            cancel()
        }
    }

    func startRecording() {
        guard phase == .idle || phase == .done || phase == .error else { return }

        guard let config = CredentialService.loadASRConfig(for: .volcano), config.isValid else {
            errorMessage = "请先在设置中配置火山引擎凭证"
            phase = .error
            logger.warning("No valid ASR config found")
            return
        }

        lastTranscript = ""
        errorMessage = ""
        phase = .recording

        phaseTask?.cancel()
        phaseTask = Task { [weak self] in
            guard let self else { return }
            await self.session.start(config: config)

            guard !Task.isCancelled else { return }
            let result = await self.session.lastResult
            self.lastTranscript = result
            if !result.isEmpty {
                self.addHistory(result)
            }
        }

        // Observe phase events from the session
        Task { [weak self] in
            guard let self else { return }
            let events = await self.session.phaseEvents
            for await sessionPhase in events {
                guard !Task.isCancelled else { break }
                self.phase = Self.mapPhase(sessionPhase)
                if case .error(let msg) = sessionPhase {
                    self.errorMessage = msg
                }
            }
        }
    }

    func cancel() {
        phaseTask?.cancel()
        phaseTask = nil
        Task { await session.cancel() }
        phase = .idle
    }

    private func setupAudioLevelForwarding() {
        session.setAudioLevelHandler { [weak self] level in
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }
    }

    private static func mapPhase(_ p: RecognitionSession.Phase) -> Phase {
        switch p {
        case .idle: return .idle
        case .recording: return .recording
        case .transcribing: return .transcribing
        case .optimizing: return .optimizing
        case .injecting: return .injecting
        case .done: return .done
        case .error: return .error
        }
    }

    // MARK: - Floating bar

    private func updateFloatingBar() {
        switch phase {
        case .recording, .transcribing, .optimizing, .injecting:
            floatingBar.show(
                phase: phase.label,
                audioLevel: audioLevel,
                transcript: lastTranscript
            )
        case .done:
            floatingBar.hide(after: 1.5)
        case .error:
            floatingBar.hide(after: 2.0)
        case .idle:
            floatingBar.hideImmediately()
        }
    }

    private func updateFloatingBarLevel() {
        guard phase == .recording else { return }
        floatingBar.update(
            phase: phase.label,
            audioLevel: audioLevel,
            transcript: lastTranscript
        )
    }

    // MARK: - History

    private func addHistory(_ text: String) {
        let item = HistoryItem(text: text, timestamp: Date())
        history.insert(item, at: 0)
        if history.count > 20 {
            history = Array(history.prefix(20))
        }
    }
}
