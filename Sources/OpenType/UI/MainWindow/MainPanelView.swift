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
            } else {
                settingsTab
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
            selectedTab = tag
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
        }
        .buttonStyle(.plain)
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

// MARK: - History Item & Row

struct HistoryItem: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: timestamp)
    }
}

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
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.text, forType: .string)
        }
    }
}
