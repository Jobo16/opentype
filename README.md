# OpenType

> macOS 语音输入法 — 按住快捷键说话，文字自动粘贴到当前应用

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/Platform-macOS%2014+-lightgrey.svg)

## Demo

> **视频链接（请在截止前补充）**

## 功能特性

- **流式语音识别** — 说话时实时显示识别结果
- **火山引擎大模型 ASR** — 高精度中英文识别，无需本地模型
- **LLM 文本后处理** — 去口头禅、纠正语法、翻译（开发中）
- **自定义热词** — 提升专有名词识别准确率
- **菜单栏常驻** — 轻量无 Dock 图标
- **全局快捷键** — 在任意应用中使用
- **自动粘贴** — 识别结果直接注入当前输入框

## 系统要求

- macOS 14+ (Sonoma)
- 火山引擎账号（App ID + Access Token）
- 麦克风权限
- 辅助功能权限（全局快捷键 + 文本注入）

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/{owner}/opentype.git
cd opentype

# 编译运行
swift build
swift run OpenType
```

### 配置 ASR 凭证

1. 注册 [火山引擎](https://www.volcengine.com) 账号
2. 开通「流式语音识别大模型」服务
3. 创建 App ID 和 Access Token
4. 在 OpenType 设置 → 语音识别 中填入凭证

## 项目结构

```
opentype/
├── Sources/OpenType/
│   ├── Protocol/          火山引擎二进制帧协议
│   ├── ASR/               ASR 抽象层 + 火山流式客户端
│   ├── Audio/             AVFoundation 16kHz 音频采集
│   ├── Session/           核心状态机（录音 → ASR → 粘贴）
│   ├── Injection/         剪贴板保存恢复 + Cmd+V
│   ├── LLM/               LLM 文本后处理（开发中）
│   ├── Input/             全局快捷键管理（开发中）
│   ├── Services/          凭证存储等服务（开发中）
│   └── UI/                设置界面、浮动条、菜单栏
├── docs/                  项目文档
├── Package.swift          SPM 包描述
└── CLAUDE.md              架构开发指南
```

## 技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 语言 | Swift 6.2 | 原生 macOS 开发 |
| UI | SwiftUI | 设置界面 + 菜单栏 |
| 音频 | AVFoundation | 16kHz 单声道 PCM 采集 |
| ASR | 火山引擎 WebSocket | 流式语音识别大模型 |
| 并发 | Swift Actors | 线程安全的状态机 |
| 包管理 | Swift Package Manager | 无第三方依赖 |

## 第三方依赖

本项目为**纯 Swift 实现**，不依赖任何第三方库。所有功能均基于 Apple 原生框架（AVFoundation、SwiftUI、CryptoKit）和系统 API 实现。

## 开发文档

- [议题要求](docs/REQUIREMENTS.md) — 完整评审规则与提交规范
- [CLAUDE.md](CLAUDE.md) — 架构设计与开发指南

## 开发路线

- [x] 项目初始化与基础架构
- [x] 火山引擎二进制帧协议实现
- [x] 火山引擎流式 ASR 客户端
- [x] 音频采集引擎（16kHz mono）
- [x] 核心状态机（录音 → ASR → 粘贴）
- [x] 文本注入（剪贴板 + Cmd+V）
- [ ] 全局快捷键管理
- [ ] 浮动条 UI（录音状态实时展示）
- [ ] LLM 文本后处理
- [ ] 设置界面完善（凭证输入、热词管理）
- [ ] App 打包签名与 DMG

## License

MIT
