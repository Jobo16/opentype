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
        .frame(width: 520, height: 360)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("OpenType 设置")
                .font(.headline)
        }
        .padding()
    }
}

struct ASRSettingsView: View {
    var body: some View {
        Form {
            Text("语音识别设置")
                .font(.headline)
            Text("火山引擎 ASR 配置")
        }
        .padding()
    }
}

struct LLMSettingsView: View {
    var body: some View {
        Form {
            Text("LLM 设置")
                .font(.headline)
        }
        .padding()
    }
}
