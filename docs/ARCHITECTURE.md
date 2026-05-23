# 技术架构选型

## 为什么选云端 ASR，不用本地模型？

| 方案 | 优点 | 缺点 |
|---|---|---|
| 本地 Whisper | 离线可用、无 API 成本 | 需要下载 1-3GB 模型、首次识别慢、占用 CPU/GPU |
| 本地 FunASR/Paraformer | 中文效果好 | 同上，且需要 Python 运行时 |
| **云端 ASR（火山引擎）** | **识别精度高、响应快、零本地依赖** | **需要网络、有 API 成本** |

**决策**：作为 menu-bar 工具，用户期望「按下就用、秒级响应」。本地模型的冷启动和资源占用不适合这个场景。火山引擎大模型 ASR 的延迟（首包 ~300ms）和精度（中文 CER < 5%）完全满足需求。

## 为什么选火山引擎而不是其他 ASR？

- **价格优势**：按量计费，每秒音频成本极低，适合高频使用
- **中文优化**：针对中文场景深度优化，支持方言和中英混读
- **流式输出**：支持边说边出结果，用户体验好
- **协议简单**：WebSocket + 自定义二进制帧协议，无需 HMAC 签名，实现成本低

## 为什么选 DeepSeek 做 LLM 后处理？

| 方案 | 延迟 | 成本 | 效果 |
|---|---|---|---|
| GPT-4o | ~2s | 高 | 好 |
| GPT-4o-mini | ~1s | 中 | 好 |
| **DeepSeek v4-flash** | **~0.5s** | **极低** | **好** |
| 本地小模型 | ~3s | 零 | 一般 |

**决策**：语音后处理需要低延迟（用户说完话等不了 2 秒），DeepSeek v4-flash 在速度和效果之间取得了最佳平衡。API 兼容 OpenAI 格式，接入成本几乎为零。

## 为什么不用 CGEvent Tap 做全局热键？

| 方案 | 优点 | 缺点 |
|---|---|---|
| CGEvent Tap | 可消费事件、精确控制 | 需要 Accessibility 权限、未签名 app 经常静默失败 |
| **NSEvent Monitor** | **无需额外权限、稳定可靠** | **不能消费事件（全局模式下）** |

**决策**：对于语音输入工具，热键的可靠性比事件消费更重要。CGEvent Tap 在未签名 app 上的问题太多（macOS 安全策略收紧），NSEvent Monitor 虽然不能消费全局事件，但实际使用中几乎没有冲突。

## 为什么用 ObservableObject 而不是 @Observable？

`@Observable`（Swift 5.9+）是 Apple 推荐的新范式，但它与 AppKit 的 `NSHostingView` 配合有兼容问题——观察上下文丢失导致 UI 不更新。

`ObservableObject` + `@Published` 虽然是旧范式，但在 `NSHostingView` 中稳定工作。对于需要与 AppKit 深度集成的 menu-bar 应用，稳定性优先。

## 为什么不用 Keychain 存凭证？

macOS 对未签名 app 的 Keychain 访问有严格限制——每次访问都弹密码确认框。这在开发阶段体验极差。

JSON 文件存储虽然安全性稍低（API Key 明文），但对于个人桌面工具完全可以接受。文件权限设为 600（仅当前用户可读写），提供了基本的安全保障。

## 并发模型：Actor + @MainActor

```
┌─────────────────────────────────────────┐
│              @MainActor                  │
│  AppState (ObservableObject)            │
│  ├── 更新 UI 状态                       │
│  ├── 管理主窗口                         │
│  └── 协调各组件                         │
└──────────────┬──────────────────────────┘
               │ async/await
┌──────────────▼──────────────────────────┐
│         Actor 隔离层                     │
│  RecognitionSession                     │
│  ├── AudioCaptureEngine (Actor)         │
│  └── VolcASRClient (Actor)              │
└─────────────────────────────────────────┘
```

- **Actor** 保证音频采集、ASR 通信的线程安全，无需手动加锁
- **@MainActor** 保证 UI 更新在主线程，避免 SwiftUI 崩溃
- 两者通过 `async/await` 桥接，代码简洁且安全
