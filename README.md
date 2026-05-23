<div align="center">

<img src="build/icon_1024.png" width="120" />

# OpenType

### 语音输入，一说即达

macOS 菜单栏语音输入工具 — 按下快捷键说话，文字自动粘贴到当前应用

![Platform](https://img.shields.io/badge/Platform-macOS%2014+-000000?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.10+-F05138?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-000000?style=flat-square)

[功能特性](#功能特性) · [快速开始](#快速开始) · [使用方式](#使用方式) · [技术架构](#技术架构) · [文档](#文档)

</div>

---

## Demo

> **🎬 视频链接（请在截止前补充）**

---

## 功能特性

<table>
<tr>
<td width="50%">

**🎙️ 语音输入**

按下 `Option+Space` 开始说话，松开自动识别并粘贴。支持中英文混合识别，实时显示识别结果。

</td>
<td width="50%">

**🧠 智能优化**

DeepSeek 大模型自动后处理：去口头禅、修同音字、补标点、数字格式化、中英混读恢复。

</td>
</tr>
<tr>
<td>

**⚡ 浮动状态条**

录音/识别过程中屏幕顶部实时显示状态、音量和识别文本，不干扰当前工作。

</td>
<td>

**🎯 全局快捷键**

在任意应用中一键触发，支持自定义键位组合。NSEvent Monitor 实现，稳定可靠。

</td>
</tr>
<tr>
<td>

**📋 历史记录**

主窗口自动保存最近识别结果，点击即可复制，支持回溯查找。

</td>
<td>

**🔧 统一设置**

主窗口内直接配置热键、ASR 凭证、LLM 设置，支持 API 连接测试。

</td>
</tr>
</table>

---

## 快速开始

### 安装

```bash
# 方式一：源码编译
git clone https://github.com/{owner}/opentype.git
cd opentype
swift build -c release
cp -R build/OpenType.app /Applications/

# 方式二：直接打开打包好的应用
open /Applications/OpenType.app
```

### 配置

**第一步：获取火山引擎凭证**

1. 注册 [火山引擎](https://www.volcengine.com) 账号
2. 开通「流式语音识别」服务
3. 创建应用，获取 **App ID** 和 **Access Token**

**第二步：在 OpenType 中配置**

1. 打开主窗口 → 设置 Tab
2. 填入 App ID 和 Access Token
3. 点击「测试」验证连接
4. 点击「保存」

**第三步（可选）：开启 LLM 优化**

1. 在设置中开启「LLM 文本优化」
2. 填入 [DeepSeek](https://platform.deepseek.com) API Key
3. 点击「测试」验证连接

### 权限

首次使用时 macOS 会请求以下权限：

| 权限 | 用途 | 必须 |
|---|---|---|
| 麦克风 | 语音采集 | ✅ |
| 辅助功能 | 文本注入到其他应用 | ✅ |

---

## 使用方式

```
┌─────────────────────────────────────────────────┐
│  OpenType                              ─  ✕     │
├──────────────┬──────────────────────────────────┤
│   录音       │   设置                           │
├──────────────┴──────────────────────────────────┤
│                                                 │
│              ┌─────────────┐                    │
│              │  🔴  大按钮  │                    │
│              │   就绪       │                    │
│              │  ━━━━━━━━━   │  ← 音量条          │
│              └─────────────┘                    │
│                                                 │
│  最近识别                                        │
│  > 你好世界 (12:30)                              │
│  > 这是一段测试文本 (12:28)                       │
│                                                 │
├─────────────────────────────────────────────────┤
│  ⚙️ 设置    🔑 快捷键: Option+Space             │
└─────────────────────────────────────────────────┘
```

| 操作 | 方式 |
|---|---|
| 开始 / 停止录音 | 按 `Option+Space` 或点击录音按钮 |
| 打开主窗口 | 点击菜单栏图标 → 主窗口 |
| 复制识别结果 | 主窗口历史记录中点击即可 |
| 退出应用 | 菜单栏 → 退出 |

---

## 技术架构

### 管线流程

```
快捷键触发 → 音频采集(16kHz) → 火山引擎ASR → DeepSeek优化(可选) → 自动粘贴
```

### 系统架构

```
                    ┌──────────────────┐
                    │   MainPanelView   │
                    │  (录音 + 设置)    │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │     AppState      │
                    │  @MainActor       │
                    │  ObservableObject │
                    └────────┬─────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
┌─────────▼────────┐ ┌──────▼──────┐ ┌─────────▼────────┐
│  HotkeyManager    │ │ Recognition │ │ FloatingBar       │
│  NSEvent Monitor  │ │   Session   │ │  Controller       │
└──────────────────┘ │   (Actor)   │ └──────────────────┘
                     └──────┬──────┘
                            │
               ┌────────────┼────────────┐
               │                         │
      ┌────────▼────────┐      ┌─────────▼─────────┐
      │ AudioCapture     │      │  VolcASRClient     │
      │ Engine (Actor)   │      │  WebSocket 流式    │
      └─────────────────┘      └─────────┬─────────┘
                                         │
                                ┌────────▼─────────┐
                                │  DeepSeekClient    │
                                │  LLM 后处理(可选)  │
                                └──────────────────┘
```

### 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 语言 | Swift 5.10 | 纯原生 macOS 开发 |
| UI | SwiftUI + AppKit | 主窗口 + 菜单栏 + 浮动条 |
| 音频 | AVFoundation | 16kHz 单声道 PCM 采集 |
| ASR | 火山引擎 WebSocket | 流式语音识别大模型 |
| LLM | DeepSeek API | OpenAI 兼容，文本后处理 |
| 并发 | Actor + @MainActor | 线程安全的状态管理 |
| 存储 | JSON + UserDefaults | 凭证与配置持久化 |
| 包管理 | Swift Package Manager | **零第三方依赖** |

---

## 项目结构

```
Sources/OpenType/
├── OpenTypeApp.swift              # 应用入口
├── AppState.swift                 # 中央状态协调器
├── Protocol/                      # 火山引擎二进制帧协议
├── ASR/                           # ASR 抽象层 + 火山客户端
├── Audio/                         # 音频采集引擎
├── Session/                       # 核心状态机
├── Injection/                     # 文本注入（剪贴板 + Cmd+V）
├── LLM/                           # DeepSeek LLM 后处理
├── Input/                         # 全局快捷键管理
├── Services/                      # 凭证存储服务
└── UI/
    ├── MainWindow/                # 主窗口（录音 + 设置）
    ├── FloatingBar/               # 录音浮动状态条
    ├── MenuBarView.swift          # 菜单栏
    └── HotKeyField.swift          # 快捷键捕获控件
```

---

## 文档

| 文档 | 说明 |
|---|---|
| [技术架构选型](docs/ARCHITECTURE.md) | 技术方案对比与设计决策 |
| [功能路线图](docs/ROADMAP.md) | 已完成、计划中、远期愿景 |
| [问题与解决方案](docs/TROUBLESHOOTING.md) | 开发过程中遇到的 9 个关键问题及解法 |
| [议题要求](docs/REQUIREMENTS.md) | 完整评审规则与提交规范 |
| [CLAUDE.md](CLAUDE.md) | 架构设计与开发指南 |

---

## 第三方依赖

本项目为 **纯 Swift 实现**，不依赖任何第三方库。

所有功能均基于 Apple 原生框架（AVFoundation、SwiftUI、AppKit）和系统 API 实现。

外部 API 服务：
- **火山引擎** — 流式语音识别（WebSocket）
- **DeepSeek** — LLM 文本后处理（REST API，可选）

---

## License

[MIT](LICENSE)
