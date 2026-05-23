import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gear") }
            ASRSettingsView()
                .tabItem { Label("语音识别", systemImage: "waveform") }
        }
        .frame(width: 460, height: 320)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @State private var hotkeyString = CredentialService.hotkeyString

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("全局快捷键")
                    Spacer()
                    TextField("例: Option+Space", text: $hotkeyString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onChange(of: hotkeyString) { _, newValue in
                            CredentialService.hotkeyString = newValue
                        }
                }
            } header: {
                Text("快捷键")
            }

            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - ASR Settings

struct ASRSettingsView: View {
    @State private var appKey: String = ""
    @State private var accessKey: String = ""
    @State private var resourceId: String = VolcanoASRConfig.resourceIdAuto
    @State private var saveError: String = ""
    @State private var saveSuccess = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("App ID")
                    Spacer()
                    TextField("火山引擎 App ID", text: $appKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                HStack {
                    Text("Access Token")
                    Spacer()
                    SecureField("火山引擎 Access Token", text: $accessKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                HStack {
                    Text("识别模型")
                    Spacer()
                    Picker("", selection: $resourceId) {
                        Text("自动（优先 2.0）").tag(VolcanoASRConfig.resourceIdAuto)
                        Text("流式语音识别 2.0").tag(VolcanoASRConfig.resourceIdSeedASR)
                        Text("流式语音识别大模型").tag(VolcanoASRConfig.resourceIdBigASR)
                    }
                    .frame(width: 240)
                }
            } header: {
                Text("火山引擎配置")
            } footer: {
                Text("在火山引擎控制台创建应用获取 App ID 和 Access Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if saveSuccess {
                        Text("已保存")
                            .foregroundStyle(.green)
                    }
                    if !saveError.isEmpty {
                        Text(saveError)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("保存") {
                        saveCredentials()
                    }
                }
            }
        }
        .padding()
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
}
