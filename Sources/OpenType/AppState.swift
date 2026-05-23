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
    @Published var historyRecords: [HistoryStore.Record] = []
    @Published var historySearch: String = ""

    // MARK: - Dependencies

    private let session = RecognitionSession()
    private let hotkeyManager = HotkeyManager()
    private let floatingBar = FloatingBarController()
    let mainWindow = MainWindowController()
    private let historyStore = HistoryStore.shared
    private var phaseTask: Task<Void, Never>?
    private var recordingStartTime: Date?
    private var lastRawText: String = ""

    // MARK: - Init

    func setup() {
        loadHotkey()
        setupHotkeyCallback()
        setupAudioLevelForwarding()
        mainWindow.configure(appState: self)
        loadHistory()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainWindow()
        }
    }

    // MARK: - Main Window

    func toggleMainWindow() { mainWindow.toggle() }
    func showMainWindow() { mainWindow.show() }

    // MARK: - Hotkey

    private func loadHotkey() {
        let raw = CredentialService.hotkeyString
        hotkeyDisplayName = HotkeyManager.Binding.parse(raw)?.displayName ?? raw
    }

    private func setupHotkeyCallback() {
        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in self?.toggleRecording() }
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

    // MARK: - Recording

    func toggleRecording() {
        switch phase {
        case .idle, .done, .error: startRecording()
        case .recording, .transcribing, .optimizing, .injecting: cancel()
        }
    }

    func startRecording() {
        guard phase == .idle || phase == .done || phase == .error else { return }

        guard let config = CredentialService.loadASRConfig(for: .volcano), config.isValid else {
            errorMessage = "请先在设置中配置火山引擎凭证"
            phase = .error
            return
        }

        lastTranscript = ""
        lastRawText = ""
        errorMessage = ""
        recordingStartTime = Date()
        phase = .recording

        phaseTask?.cancel()
        phaseTask = Task { [weak self] in
            guard let self else { return }
            await self.session.start(config: config)

            guard !Task.isCancelled else { return }
            let raw = await self.session.lastRawText
            let optimized = await self.session.lastResult
            let duration = self.recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

            self.lastRawText = raw
            self.lastTranscript = optimized.isEmpty ? raw : optimized

            if !raw.isEmpty {
                self.saveHistoryRecord(raw: raw, optimized: optimized, duration: duration)
            }
        }

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
            Task { @MainActor [weak self] in self?.audioLevel = level }
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
            floatingBar.show(phase: phase.label, audioLevel: audioLevel, transcript: lastTranscript)
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
        floatingBar.update(phase: phase.label, audioLevel: audioLevel, transcript: lastTranscript)
    }

    // MARK: - History

    func loadHistory() {
        if historySearch.isEmpty {
            historyRecords = historyStore.getAll()
        } else {
            historyRecords = historyStore.search(keyword: historySearch)
        }
    }

    private func saveHistoryRecord(raw: String, optimized: String, duration: TimeInterval) {
        let record = HistoryStore.Record(
            rawText: raw,
            optimizedText: optimized,
            mode: CredentialService.isLLMEnabled ? "llm" : "direct",
            duration: duration
        )
        historyStore.add(record)
        loadHistory()
    }

    func deleteHistory(id: UUID) {
        historyStore.delete(id: id)
        loadHistory()
    }

    func clearHistory() {
        historyStore.deleteAll()
        loadHistory()
    }

    func searchHistory(_ keyword: String) {
        historySearch = keyword
        loadHistory()
    }

    func exportHistoryCSV() -> URL? {
        let records = historySearch.isEmpty ? nil : historyRecords
        return historyStore.exportCSV(filtered: records)
    }

    func insertTextFromHistory(_ text: String) {
        let injector = TextInjectionEngine()
        Task { try? await injector.inject(text) }
    }

    // MARK: - Auto-learning from edits

    func learnFromEdit(original: String, corrected: String) {
        let replacements = WordDiff.detectReplacements(original: original, corrected: corrected)
        guard !replacements.isEmpty else { return }

        logger.info("Detected \(replacements.count) correction(s) from edit")

        Task {
            for replacement in replacements {
                let added = await HotwordStore.shared.addWithLLMValidation(replacement.corrected)
                if added {
                    logger.info("Auto-learned hotword: \(replacement.corrected)")
                }
            }
        }
    }
}
