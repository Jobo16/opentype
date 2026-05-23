import SwiftUI

/// Main app window — single unified interface with Recording and Settings tabs.
struct MainPanelView: View {
    @ObservedObject var appState: AppState
    @State private var selectedTab = "record"

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Divider()

            // Tab content
            if selectedTab == "record" {
                recordTab
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                settingsTab
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: 420, height: 480)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("录音", icon: "mic.fill", tag: "record")
            tabButton("设置", icon: "gearshape.fill", tag: "settings")
            Spacer()
        }
    }

    private func tabButton(_ title: String, icon: String, tag: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 13, weight: selectedTab == tag ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedTab == tag ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(selectedTab == tag ? Color.accentColor : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: - Record Tab

    private var recordTab: some View {
        VStack(spacing: 0) {
            // Record button + status
            recordSection
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            // History list
            historySection
        }
    }

    private var recordSection: some View {
        VStack(spacing: 10) {
            // Big record button
            Button {
                appState.toggleRecording()
            } label: {
                ZStack {
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

                    Circle()
                        .fill(appState.phase == .recording ? .red : .primary)
                        .frame(width: 60, height: 60)
                        .shadow(color: appState.phase == .recording ? .red.opacity(0.4) : .clear, radius: 12)

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
            .focusEffectDisabled()
            .scaleEffect(appState.phase == .recording ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: appState.phase == .recording)

            Text(appState.phase.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(appState.phase == .recording ? .red : .primary)

            // Audio level bar
            audioLevelBar
                .frame(width: 200, height: 4)
                .opacity(appState.phase == .recording ? 1 : 0.3)

            if !appState.lastTranscript.isEmpty && appState.phase == .idle {
                Text(appState.lastTranscript)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

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
            // Header + search
            HStack(spacing: 8) {
                Text("历史记录")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(appState.historyRecords.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()

                // Export CSV
                Button {
                    if let url = appState.exportHistoryCSV() {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("导出 CSV")

                // Clear all
                Button {
                    appState.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("清空历史")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索…", text: Binding(
                    get: { appState.historySearch },
                    set: { appState.searchHistory($0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12))

                if !appState.historySearch.isEmpty {
                    Button {
                        appState.searchHistory("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            Divider()

            // Records list
            if appState.historyRecords.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.justify.left")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(appState.historySearch.isEmpty ? "暂无识别记录" : "无匹配结果")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.historyRecords) { record in
                            HistoryRecordRow(record: record, appState: appState)
                            if record.id != appState.historyRecords.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hotkey
                settingsSection("快捷键") {
                    HotKeyField(hotkeyString: Binding(
                        get: { CredentialService.hotkeyString },
                        set: { CredentialService.hotkeyString = $0; appState.enableHotkey() }
                    ))
                }

                // ASR
                settingsSection("语音识别 (火山引擎)") {
                    ASRSettingsInline()
                }

                // LLM
                settingsSection("LLM 文本优化 (DeepSeek)") {
                    LLMSettingsInline()
                }

                // Hotwords
                settingsSection("热词管理") {
                    HotwordManagerView()
                }

                // Version
                HStack {
                    Text("版本")
                        .font(.system(size: 12))
                    Spacer()
                    Text("1.0.0")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Inline Settings Views

struct ASRSettingsInline: View {
    @State private var appKey: String = ""
    @State private var accessKey: String = ""
    @State private var resourceId: String = VolcanoASRConfig.resourceIdAuto
    @State private var saveError: String = ""
    @State private var saveSuccess = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("App ID").frame(width: 80, alignment: .trailing)
                TextField("火山引擎 App ID", text: $appKey)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("Access Token").frame(width: 80, alignment: .trailing)
                SecureField("Access Token", text: $accessKey)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("识别模型").frame(width: 80, alignment: .trailing)
                Picker("", selection: $resourceId) {
                    Text("自动").tag(VolcanoASRConfig.resourceIdAuto)
                    Text("2.0").tag(VolcanoASRConfig.resourceIdSeedASR)
                    Text("大模型").tag(VolcanoASRConfig.resourceIdBigASR)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                if saveSuccess { Text("已保存").font(.caption).foregroundStyle(.green) }
                if let err = testResult { Text(err).font(.caption).foregroundStyle(err.contains("成功") ? .green : .red) }
                Spacer()
                if isTesting { ProgressView().controlSize(.small) }
                Button("测试") { test() }.disabled(isTesting || appKey.isEmpty || accessKey.isEmpty)
                Button("保存") { save() }
            }
            .font(.caption)
        }
        .onAppear { load() }
    }

    private func load() {
        if let v = CredentialService.loadASRCredentials(for: .volcano) {
            appKey = v["appKey"] ?? ""
            accessKey = v["accessKey"] ?? ""
            resourceId = v["resourceId"] ?? VolcanoASRConfig.resourceIdAuto
        }
    }

    private func save() {
        saveError = ""; saveSuccess = false; testResult = nil
        do {
            try CredentialService.saveASRCredentials(for: .volcano, values: [
                "appKey": appKey, "accessKey": accessKey, "resourceId": resourceId
            ])
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func test() {
        isTesting = true; testResult = nil
        let resolved = resourceId == "auto" || resourceId.isEmpty
            ? VolcanoASRConfig.resourceIdSeedASR : resourceId
        Task {
            let result = await VolcanoConnectionTester.test(
                appKey: appKey, accessKey: accessKey, resourceId: resolved
            )
            isTesting = false
            switch result {
            case .success(let msg): testResult = msg
            case .failure(let msg): testResult = msg
            }
        }
    }
}

struct LLMSettingsInline: View {
    @State private var enabled = CredentialService.isLLMEnabled
    @State private var apiKey: String = ""
    @State private var model: String = "deepseek-v4-flash"
    @State private var baseURL: String = "https://api.deepseek.com"
    @State private var saveSuccess = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        VStack(spacing: 8) {
            Toggle("启用 LLM 优化", isOn: $enabled)
                .onChange(of: enabled) { _, v in CredentialService.isLLMEnabled = v }
                .font(.system(size: 12))

            if enabled {
                HStack {
                    Text("API Key").frame(width: 80, alignment: .trailing)
                    SecureField("DeepSeek API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("模型").frame(width: 80, alignment: .trailing)
                    Picker("", selection: $model) {
                        Text("v4-flash (快)").tag("deepseek-v4-flash")
                        Text("v4-pro (准)").tag("deepseek-v4-pro")
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Text("API 地址").frame(width: 80, alignment: .trailing)
                    TextField("https://api.deepseek.com", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    if saveSuccess { Text("已保存").font(.caption).foregroundStyle(.green) }
                    if let err = testResult { Text(err).font(.caption).foregroundStyle(err.contains("成功") ? .green : .red) }
                    Spacer()
                    if isTesting { ProgressView().controlSize(.small) }
                    Button("测试") { test() }.disabled(isTesting || apiKey.isEmpty)
                    Button("保存") { save() }
                }
                .font(.caption)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        let c = CredentialService.loadLLMConfig()
        apiKey = c.apiKey; model = c.model; baseURL = c.baseURL
    }

    private func save() {
        saveSuccess = false; testResult = nil
        do {
            try CredentialService.saveLLMConfig(LLMConfig(apiKey: apiKey, model: model, baseURL: baseURL))
            saveSuccess = true
        } catch {}
    }

    private func test() {
        isTesting = true; testResult = nil
        Task {
            let client = DeepSeekClient()
            do {
                _ = try await client.chat(
                    systemPrompt: "Reply with exactly: OK",
                    userMessage: "ping",
                    config: LLMConfig(apiKey: apiKey, model: model, baseURL: baseURL)
                )
                isTesting = false; testResult = "连接成功"
            } catch {
                isTesting = false; testResult = "失败: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - History Record Row

struct HistoryRecordRow: View {
    let record: HistoryStore.Record
    @ObservedObject var appState: AppState
    @State private var copied = false
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: record.timestamp)
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MM/dd"
        return f.string(from: record.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Show raw text if LLM optimized
                if !record.optimizedText.isEmpty && record.rawText != record.optimizedText {
                    Text("原文: \(record.rawText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("\(dateString) \(timeString)")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                    if record.duration > 0 {
                        Text(String(format: "%.1fs", record.duration))
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                    if record.mode == "llm" {
                        Text("LLM")
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 2))
                            .foregroundStyle(.purple)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                // Copy
                Button {
                    copyToClipboard(record.displayText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("复制文本")

                // Re-insert at cursor
                Button {
                    appState.insertTextFromHistory(record.displayText)
                } label: {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("插入到光标位置")

                // Edit (triggers auto-learning)
                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("编辑并学习修正")

                // Delete
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("删除")
                .alert("确认删除", isPresented: $showDeleteConfirm) {
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) {
                        appState.deleteHistory(id: record.id)
                    }
                } message: {
                    Text("确定要删除这条记录吗？")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            copyToClipboard(record.displayText)
        }
        .sheet(isPresented: $showEditSheet) {
            EditHistorySheet(record: record) { editedText in
                appState.learnFromEdit(original: record.rawText, corrected: editedText)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Hotword Manager View

struct HotwordManagerView: View {
    @State private var entries: [HotwordStore.Entry] = []
    @State private var newWord: String = ""
    @State private var showBulkEdit = false
    @State private var bulkText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Add single word
            HStack(spacing: 6) {
                TextField("添加热词…", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWord() }
                Button("添加") { addWord() }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Stats + bulk edit
            HStack {
                Text("\(entries.count) 个热词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("批量编辑") { bulkText = entries.map(\.word).joined(separator: "\n"); showBulkEdit = true }
                    .font(.caption)
                Button("清空") { entries = []; HotwordStore.shared.clearAll() }
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Tag flow
            if entries.isEmpty {
                Text("暂无热词，添加后下次识别即生效")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(entries) { entry in
                        HStack(spacing: 4) {
                            Text(entry.word)
                                .font(.system(size: 12))
                            if entry.source == .learned {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.purple)
                            }
                            Button {
                                removeWord(entry)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(entry.source == .learned ? Color.purple.opacity(0.08) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $showBulkEdit) {
            VStack(spacing: 12) {
                Text("批量编辑热词（每行一个）")
                    .font(.headline)
                TextEditor(text: $bulkText)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200)
                    .border(.separator)
                HStack {
                    Spacer()
                    Button("取消") { showBulkEdit = false }
                    Button("保存") { saveBulk() }
                }
            }
            .padding(20)
            .frame(width: 360, height: 300)
        }
    }

    private func load() {
        entries = HotwordStore.shared.getAll()
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        _ = HotwordStore.shared.add(word)
        newWord = ""
        load()
    }

    private func removeWord(_ entry: HotwordStore.Entry) {
        HotwordStore.shared.remove(id: entry.id)
        load()
    }

    private func saveBulk() {
        let words = bulkText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        HotwordStore.shared.clearAll()
        _ = HotwordStore.shared.addBatch(words)
        showBulkEdit = false
        load()
    }
}

// MARK: - Flow Layout (for tag wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), origins)
    }
}

// MARK: - Edit History Record Sheet

struct EditHistorySheet: View {
    let record: HistoryStore.Record
    let onSave: (String) -> Void
    @State private var editedText: String
    @Environment(\.dismiss) private var dismiss

    init(record: HistoryStore.Record, onSave: @escaping (String) -> Void) {
        self.record = record
        self.onSave = onSave
        _editedText = State(initialValue: record.displayText)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("编辑识别文本")
                .font(.headline)

            if !record.rawText.isEmpty && record.rawText != record.optimizedText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ASR 原文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.rawText)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            TextEditor(text: $editedText)
                .font(.system(size: 14))
                .frame(minHeight: 120)
                .border(.separator)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(editedText)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: 420, height: 300)
    }
}
