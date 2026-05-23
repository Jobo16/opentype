import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gear") }
            ASRSettingsView()
                .tabItem { Label("语音识别", systemImage: "waveform") }
            LLMSettingsView()
                .tabItem { Label("LLM", systemImage: "sparkles") }
        }
        .frame(width: 500, height: 380)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @State private var hotkeyString = CredentialService.hotkeyString

    var body: some View {
        Form {
            HStack {
                Text("全局快捷键")
                Spacer()
                HotKeyField(hotkeyString: $hotkeyString) { newValue in
                    CredentialService.hotkeyString = newValue
                }
            }

            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ASR Settings

struct ASRSettingsView: View {
    @State private var appKey: String = ""
    @State private var accessKey: String = ""
    @State private var resourceId: String = VolcanoASRConfig.resourceIdAuto
    @State private var saveError: String = ""
    @State private var saveSuccess = false
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("App ID", text: $appKey)
                SecureField("Access Token", text: $accessKey)
                Picker("识别模型", selection: $resourceId) {
                    Text("自动（优先 2.0）").tag(VolcanoASRConfig.resourceIdAuto)
                    Text("流式语音识别 2.0").tag(VolcanoASRConfig.resourceIdSeedASR)
                    Text("流式语音识别大模型").tag(VolcanoASRConfig.resourceIdBigASR)
                }
            } header: {
                Text("火山引擎配置")
            } footer: {
                Text("在火山引擎控制台创建应用获取 App ID 和 Access Token")
            }

            Section {
                HStack(spacing: 12) {
                    if saveSuccess {
                        Text("已保存").foregroundStyle(.green)
                    }
                    if !saveError.isEmpty {
                        Text(saveError).foregroundStyle(.red)
                    }
                    if let result = testResult {
                        switch result {
                        case .success(let msg): Text(msg).foregroundStyle(.green)
                        case .failure(let msg): Text(msg).foregroundStyle(.red)
                        }
                    }
                    Spacer()
                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("测试连接") { testConnection() }
                        .disabled(isTesting || appKey.isEmpty || accessKey.isEmpty)
                    Button("保存") { saveCredentials() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadCredentials() }
    }

    private func loadCredentials() {
        if let values = CredentialService.loadASRCredentials(for: .volcano) {
            appKey = values["appKey"] ?? ""
            accessKey = values["accessKey"] ?? ""
            resourceId = values["resourceId"] ?? VolcanoASRConfig.resourceIdAuto
        }
    }

    private func saveCredentials() {
        saveError = ""
        saveSuccess = false
        do {
            try CredentialService.saveASRCredentials(for: .volcano, values: [
                "appKey": appKey,
                "accessKey": accessKey,
                "resourceId": resourceId,
            ])
            saveSuccess = true
        } catch {
            saveError = "保存失败: \(error.localizedDescription)"
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        saveError = ""
        saveSuccess = false

        Task {
            let result = await VolcanoConnectionTester.test(
                appKey: appKey,
                accessKey: accessKey,
                resourceId: resourceId
            )
            isTesting = false
            testResult = result
        }
    }
}

// MARK: - LLM Settings

struct LLMSettingsView: View {
    @State private var enabled = CredentialService.isLLMEnabled
    @State private var apiKey: String = ""
    @State private var model: String = "deepseek-v4-flash"
    @State private var baseURL: String = "https://api.deepseek.com"
    @State private var saveError: String = ""
    @State private var saveSuccess = false
    @State private var testResult: TestResult?
    @State private var isTesting = false

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Toggle("启用 LLM 文本优化", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    CredentialService.isLLMEnabled = newValue
                }

            if enabled {
                Section {
                    SecureField("API Key", text: $apiKey)
                    Picker("模型", selection: $model) {
                        Text("deepseek-v4-flash（快速）").tag("deepseek-v4-flash")
                        Text("deepseek-v4-pro（精准）").tag("deepseek-v4-pro")
                    }
                    TextField("API 地址", text: $baseURL)
                } header: {
                    Text("DeepSeek 配置")
                } footer: {
                    Text("在 platform.deepseek.com 获取 API Key")
                }

                Section {
                    HStack(spacing: 12) {
                        if saveSuccess {
                            Text("已保存").foregroundStyle(.green)
                        }
                        if !saveError.isEmpty {
                            Text(saveError).foregroundStyle(.red)
                        }
                        if let result = testResult {
                            switch result {
                            case .success(let msg): Text(msg).foregroundStyle(.green)
                            case .failure(let msg): Text(msg).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("测试连接") { testConnection() }
                            .disabled(isTesting || apiKey.isEmpty)
                        Button("保存") { saveLLM() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadLLM() }
    }

    private func loadLLM() {
        let config = CredentialService.loadLLMConfig()
        apiKey = config.apiKey
        model = config.model
        baseURL = config.baseURL
    }

    private func saveLLM() {
        saveError = ""
        saveSuccess = false
        do {
            try CredentialService.saveLLMConfig(
                LLMConfig(apiKey: apiKey, model: model, baseURL: baseURL)
            )
            saveSuccess = true
        } catch {
            saveError = "保存失败: \(error.localizedDescription)"
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        saveError = ""
        saveSuccess = false

        Task {
            let config = LLMConfig(apiKey: apiKey, model: model, baseURL: baseURL)
            let client = DeepSeekClient()
            do {
                let reply = try await client.chat(
                    systemPrompt: "Reply with exactly: OK",
                    userMessage: "ping",
                    config: config
                )
                isTesting = false
                testResult = .success("连接成功")
            } catch {
                isTesting = false
                testResult = .failure("失败: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Volcano Engine Connection Tester

enum VolcanoConnectionTester {

    /// Resolve "auto" to the actual resource ID before sending.
    private static func resolveResourceId(_ raw: String) -> String {
        if raw == "auto" || raw.isEmpty {
            return VolcanoASRConfig.resourceIdSeedASR
        }
        return raw
    }

    static func test(
        appKey: String,
        accessKey: String,
        resourceId: String
    ) async -> ASRSettingsView.TestResult {
        let resolvedResourceId = resolveResourceId(resourceId)
        NSLog("[VolcanoTest] Testing with appKey=%@, resourceId=%@", appKey, resolvedResourceId)

        let url = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
        var request = URLRequest(url: url)
        request.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resolvedResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")
        request.timeoutInterval = 10

        return await withCheckedContinuation { continuation in
            var resumed = false
            func resumeOnce(_ result: ASRSettingsView.TestResult) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }

            let session = URLSession(configuration: .default)
            let task = session.webSocketTask(with: request)

            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + 10)
            timer.setEventHandler {
                task.cancel(with: .normalClosure, reason: nil)
                resumeOnce(.failure("连接超时"))
            }
            timer.resume()

            task.resume()

            // Send the initial handshake payload
            let payload = VolcProtocol.buildClientRequest(uid: UUID().uuidString)
            let header = VolcHeader(
                messageType: .fullClientRequest,
                flags: .noSequence,
                serialization: .json,
                compression: .none
            )
            let message = VolcProtocol.encodeMessage(header: header, payload: payload)

            task.send(.data(message)) { sendError in
                if let sendError {
                    timer.cancel()
                    NSLog("[VolcanoTest] Send failed: %@", sendError.localizedDescription)
                    resumeOnce(.failure("发送失败: \(sendError.localizedDescription)"))
                    return
                }

                NSLog("[VolcanoTest] Send succeeded, waiting for server response...")

                // Wait for server response to verify auth is valid
                task.receive { result in
                    timer.cancel()
                    switch result {
                    case .success(let message):
                        switch message {
                        case .data(let data):
                            // Try to parse the server response
                            if data.count >= 4 {
                                let headerByte1 = data[1]
                                let msgType = (headerByte1 >> 4) & 0x0F
                                if msgType == 0x0F {
                                    // Server error
                                    let detail = Self.parseServerError(data)
                                    NSLog("[VolcanoTest] Server rejected: %@", detail)
                                    resumeOnce(.failure("认证失败: \(detail)"))
                                } else {
                                    NSLog("[VolcanoTest] Got server response (type=0x%02X), auth OK", msgType)
                                    resumeOnce(.success("连接成功"))
                                }
                            } else {
                                NSLog("[VolcanoTest] Got response but too short (%d bytes)", data.count)
                                resumeOnce(.success("连接成功"))
                            }
                        case .string(let text):
                            NSLog("[VolcanoTest] Got text response: %@", text)
                            resumeOnce(.success("连接成功"))
                        @unknown default:
                            resumeOnce(.success("连接成功"))
                        }
                    case .failure(let error):
                        NSLog("[VolcanoTest] Receive failed: %@", error.localizedDescription)
                        // If receive fails immediately, it might be an auth rejection
                        let nsError = error as NSError
                        if nsError.code == 2000 || nsError.domain == "NSPOSIXErrorDomain" {
                            resumeOnce(.failure("认证失败: \(error.localizedDescription)"))
                        } else {
                            resumeOnce(.failure("接收失败: \(error.localizedDescription)"))
                        }
                    }
                }
            }
        }
    }

    private static func parseServerError(_ data: Data) -> String {
        // Parse the raw response to find error info
        guard data.count >= 4 else { return "响应数据过短" }

        // Skip header (4 bytes) and optional sequence number (4 bytes)
        var offset = 4
        let flags = data[1] & 0x0F
        if flags == 0x03 || flags == 0x01 { // negativeSequenceLast or positiveSequence
            offset += 4
        }

        guard data.count >= offset + 4 else { return "无效响应" }
        let sizeBytes = data[offset..<offset+4]
        let payloadSize = Int(UInt32(bigEndian: sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }))
        offset += 4

        guard data.count >= offset + payloadSize else { return "载荷截断" }
        let payload = data[offset..<offset+payloadSize]

        if let json = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] {
            let code = json["code"] as? Int ?? -1
            let message = json["message"] as? String ?? "未知错误"
            return "code=\(code), \(message)"
        }
        return "无法解析错误信息"
    }
}
