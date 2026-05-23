# 问题与解决方案

## 1. CGEvent Tap 全局快捷键在未签名 app 上静默失败

**现象**：设置中配置了快捷键，但按下无反应。日志中无任何错误。

**原因**：macOS 对未签名 app 的 CGEvent Tap 有安全限制。即使 `AXIsProcessTrustedWithOptions` 返回 true，tap 也可能被系统静默禁用。

**解决**：放弃 CGEvent Tap，改用 `NSEvent.addGlobalMonitorForEvents` + `addLocalMonitorForEvents`。NSEvent Monitor 不需要 Accessibility 权限即可监听全局按键事件，且在未签名 app 上稳定工作。

**权衡**：NSEvent Monitor 的全局模式不能消费事件（事件仍会传递给前台 app），但对于语音输入工具，热键可靠性比事件消费更重要。

## 2. 火山引擎 resourceId = "auto" 被服务器拒绝

**现象**：WebSocket 连接成功，但发送握手包后收到 serverError。

**原因**：`resourceId = "auto"` 是客户端的便捷选项，服务器不认识这个值。必须在发送前解析为实际的 resource ID（如 `volc.seedasr.sauc.duration`）。

**解决**：在 `VolcanoASRConfig.init` 和连接测试中，将 `"auto"` 解析为 `"volc.seedasr.sauc.duration"` 后再放入 `X-Api-Resource-Id` header。

**教训**：API 的 "auto" 选项通常是客户端逻辑，不是服务端协议的一部分。

## 3. 火山引擎连接测试误报"成功"

**现象**：点击「测试连接」显示绿色"连接成功"，但实际录音时认证失败。

**原因**：WebSocket 的 `send()` 操作在连接建立后立即返回成功，即使服务器尚未验证凭证。测试代码只检查了 `send()` 的结果，没有等待服务器响应。

**解决**：在 `send()` 之后调用 `task.receive()` 等待服务器响应。如果收到 `serverError`（消息类型 0x0F），解析错误信息并显示给用户。添加了 `resumeOnce` 防护避免 continuation 被多次 resume。

## 4. @Observable 与 NSHostingView 不兼容

**现象**：主窗口显示正常，但按钮点击无反应，UI 不更新。

**原因**：`@Observable` 宏依赖 SwiftUI 的观察追踪机制，但 `NSHostingView`（AppKit）不提供相同的追踪上下文，导致属性变化无法触发视图刷新。

**解决**：将 `AppState` 从 `@Observable` 改为 `ObservableObject` + `@Published`。将视图中的 `@Bindable` 改为 `@ObservedObject`。将 `OpenTypeApp` 中的 `@State` 改为 `@StateObject`。

**教训**：纯 SwiftUI 应用用 `@Observable` 没问题，但需要与 AppKit 深度集成时，`ObservableObject` 更可靠。

## 5. macOS 钥匙串反复弹窗

**现象**：每次启动 app 都弹出"OpenType 想要使用钥匙串中的机密信息"对话框。

**原因**：未签名 app 没有 Keychain Access Group，macOS 将每次访问视为新请求，要求用户授权。

**解决**：放弃 Keychain，改用纯 JSON 文件存储凭证（`~/Library/Application Support/OpenType/config.json`）。文件权限设为 600，仅当前用户可读写。

**权衡**：API Key 以明文存储在磁盘上，安全性略低于 Keychain。对于个人桌面工具，这个 trade-off 可以接受。

## 6. MenuBarExtra 主窗口关闭后无法重新打开

**现象**：关闭主窗口后，点击菜单栏图标无法重新打开。

**原因**：`NSWindow.close()` 会释放窗口对象。由于设置了 `isReleasedWhenClosed = false`，窗口只是隐藏了，但需要通过 `orderOut(nil)` 隐藏、`makeKeyAndOrderFront(nil)` 重新显示。

**解决**：在 `NSWindowDelegate.windowShouldClose` 中拦截关闭事件，改为 `orderOut(nil)` 隐藏窗口。添加 `toggle()` 方法在显示/隐藏之间切换。

## 7. SwiftUI Settings 场景在 MenuBarExtra 中难以激活

**现象**：点击菜单栏中的"设置"按钮，Settings 窗口不出现或不获得焦点，TextField 无法输入。

**原因**：`MenuBarExtra` 的 Settings 场景需要通过 `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` 激活，且需要 `NSApp.activate(ignoringOtherApps: true)` 确保窗口获得焦点。

**解决**：最终方案是将设置集成到主窗口的 Tab 中，彻底移除了独立的 Settings 场景。这消除了激活问题，也改善了 UX（一个窗口搞定所有）。

## 8. 浮动条 stale hide 覆盖新录音

**现象**：快速连续两次录音时，第一次录音的延迟隐藏会把第二次录音的浮动条也藏起来。

**原因**：`hide(after:)` 使用 `DispatchQueue.asyncAfter` 延迟隐藏，如果在延迟期间开始了新录音，旧的 hide 任务会把新录音的浮动条也关闭。

**解决**：引入 generation counter（`UInt64` 自增）。每次 `show()` 时 `generation &+= 1`，hide 时捕获当前 generation，执行前检查 generation 是否变化。如果变了，说明已有新录音开始，跳过 hide。

## 9. 火山引擎 ASR 丢弃 partial 的检测

**现象**：说话中间有短暂停顿时，部分识别文本丢失。

**原因**：服务器在检测到新 utterance 时，可能不确认上一个 partial 就直接开始新的。这导致中间的 partial 文本既不是 confirmed 也不再出现在后续结果中。

**解决**：实现本地 partial 提升机制。当服务器开始新 utterance 但未确认前一个 partial 时，检查 LCP（最长公共前缀）比率。如果比率 < 0.5，说明是新的 utterance 而非延续，将旧 partial 提升为本地 confirmed segment。同时添加防误提升检查：如果新 partial 与已提升的 segment 有 > 50% 的公共前缀，则撤销提升。
