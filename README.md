# OpenType

> macOS 语音输入法 — 按下快捷键说话，文字自动粘贴到当前应用

![Platform](https://img.shields.io/badge/Platform-macOS%2014+-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.10+-orange.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Demo

> **视频链接（请在截止前补充）**

## 功能特性

- **流式语音识别** — 说话时实时显示识别结果
- **火山引擎大模型 ASR** — 高精度中英文识别，云端处理，无需本地模型
- **LLM 文本后处理** — DeepSeek 大模型自动优化：去口头禅、修同音字、补标点、数字格式化
- **全局快捷键** — 在任意应用中一键触发录音（默认 Option+Space）
- **自动粘贴** — 识别结果直接注入当前输入框，无需手动操作
- **浮动状态条** — 录音/识别过程中屏幕顶部实时显示状态和文本
- **主窗口控制面板** — 统一的录音控制 + 设置配置界面
- **菜单栏常驻** — 轻量无 Dock 图标，随时可用

## 系统要求

- macOS 14+ (Sonoma)
- 火山引擎账号（App ID + Access Token）
- DeepSeek API Key（可选，用于文本优化）
- 麦克风权限
- 辅助功能权限（文本注入到其他应用）

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/{owner}/opentype.git
cd opentype

# 编译运行
swift build
swift run OpenType
```

或直接打开打包好的应用：

```bash
open build/OpenType.app
# 或复制到应用程序目录
cp -R build/OpenType.app /Applications/
```

### 配置步骤

1. 注册 [火山引擎](https://www.volcengine.com) 账号，开通「流式语音识别」服务
2. 创建应用，获取 App ID 和 Access Token
3. 打开 OpenType → 设置 → 语音识别，填入凭证并点击「测试连接」验证
4. （可选）在设置 → LLM 中填入 DeepSeek API Key 开启文本优化

## 使用方式

| 操作 | 方式 |
|---|---|
| 开始/停止录音 | 按 `Option+Space` 或点击主窗口录音按钮 |
| 打开主窗口 | 点击菜单栏图标 → 主窗口 |
| 查看设置 | 主窗口 → 设置 Tab |
| 复制识别结果 | 主窗口历史记录中点击即可复制 |

## 项目结构

```
Sources/OpenType/
├── OpenTypeApp.swift              # @main 入口（菜单栏应用）
├── AppState.swift                 # @MainActor 中央状态协调器
├── Protocol/                      # 火山引擎二进制帧协议
│   ├── VolcHeader.swift           # 4 字节帧头编解码
│   ├── VolcProtocol.swift         # 完整消息编解码 + gzip
│   └── VolcProtocolError.swift
├── ASR/                           # ASR 抽象层
│   ├── ASRProvider.swift          # Provider 枚举 + 凭证字段定义
│   ├── ASRProviderRegistry.swift  # Provider → 客户端工厂映射
│   ├── SpeechRecognizer.swift     # 核心协议 + 识别事件/转录类型
│   ├── VolcanoASRConfig.swift     # 火山引擎凭证配置
│   └── VolcASRClient.swift        # WebSocket 流式客户端
├── Audio/
│   └── AudioCaptureEngine.swift   # AVFoundation 16kHz 单声道采集
├── Session/
│   └── RecognitionSession.swift   # 核心状态机：录音 → ASR → LLM → 粘贴
├── Injection/
│   └── TextInjectionEngine.swift  # 剪贴板保存/恢复 + Cmd+V
├── LLM/                           # LLM 文本后处理
│   ├── LLMClient.swift            # 协议 + LLMConfig
│   ├── DeepSeekClient.swift       # DeepSeek API 客户端（OpenAI 兼容）
│   └── PromptBuilder.swift        # 语音后处理 System Prompt
├── Input/
│   └── HotkeyManager.swift        # 全局快捷键（NSEvent monitor）
├── Services/
│   └── CredentialService.swift    # JSON 凭证存储（ASR + LLM）
└── UI/
    ├── MenuBarView.swift           # 菜单栏下拉菜单
    ├── HotKeyField.swift           # 快捷键捕获控件
    ├── FloatingBar/                # 录音时浮动状态条
    │   ├── FloatingBarController.swift
    │   └── FloatingBarView.swift
    ├── MainWindow/                 # 主窗口控制面板
    │   ├── MainPanelView.swift     # 录音 + 设置 Tab 界面
    │   └── MainWindowController.swift
    └── Settings/
        └── SettingsView.swift      # 独立设置窗口（备用）
```

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 语言 | Swift 5.10 | 原生 macOS 开发 |
| UI | SwiftUI + AppKit | 主窗口 + 菜单栏 + 浮动条 |
| 音频 | AVFoundation | 16kHz 单声道 PCM 采集 |
| ASR | 火山引擎 WebSocket | 流式语音识别大模型 |
| LLM | DeepSeek API | OpenAI 兼容接口，文本后处理 |
| 并发 | Swift Actors + @MainActor | 线程安全的状态管理 |
| 存储 | JSON + UserDefaults | 凭证与配置持久化 |
| 包管理 | Swift Package Manager | 零第三方依赖 |

## 第三方依赖

本项目为**纯 Swift 实现**，不依赖任何第三方库。所有功能均基于 Apple 原生框架（AVFoundation、SwiftUI、AppKit）和系统 API 实现。

外部 API 服务：
- **火山引擎** — 流式语音识别（WebSocket）
- **DeepSeek** — LLM 文本后处理（REST API，可选）

## 架构概览

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  HotkeyManager│────▶│RecognitionSession│────▶│TextInjection │
│  (NSEvent)   │     │  (Actor)     │     │  Engine      │
└─────────────┘     └──────┬───────┘     └──────────────┘
                           │
                    ┌──────┴───────┐
                    │              │
              ┌─────▼─────┐ ┌─────▼─────┐
              │AudioCapture│ │VolcASRClient│
              │  Engine    │ │ (WebSocket) │
              └───────────┘ └───────────┘
                                  │
                           ┌──────▼──────┐
                           │DeepSeekClient│
                           │  (可选 LLM)  │
                           └─────────────┘
```

**管线流程：** 热键触发 → 录音 → ASR 识别 → LLM 优化（可选） → 自动粘贴

## 开发文档

- [议题要求](docs/REQUIREMENTS.md) — 完整评审规则与提交规范
- [技术架构选型](docs/ARCHITECTURE.md) — 技术方案对比与设计决策
- [功能路线图](docs/ROADMAP.md) — 已完成、计划中、远期愿景
- [问题与解决方案](docs/TROUBLESHOOTING.md) — 开发过程中遇到的 9 个关键问题及解法
- [CLAUDE.md](CLAUDE.md) — 架构设计与开发指南

## 开发路线

- [x] 项目初始化与基础架构
- [x] 火山引擎二进制帧协议实现
- [x] 火山引擎流式 ASR 客户端
- [x] 音频采集引擎（16kHz mono）
- [x] 核心状态机（录音 → ASR → 粘贴）
- [x] 文本注入（剪贴板 + Cmd+V）
- [x] 全局快捷键管理（NSEvent monitor）
- [x] 浮动状态条（实时音量 + 状态显示）
- [x] LLM 文本后处理（DeepSeek API）
- [x] 主窗口控制面板（录音 + 设置 Tab）
- [x] 菜单栏集成
- [x] 凭证存储（JSON）
- [x] API 连接测试功能
- [x] .app 打包
- [ ] App 签名与 DMG 分发

## License

MIT
