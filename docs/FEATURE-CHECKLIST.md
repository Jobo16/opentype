# 功能扩展清单

> 对标 Type4Me / Input0，OpenType 待实现的功能清单。
> 完成一项勾一项，每个条目附实现位置建议。

---

## 二、词汇系统

- [x] **热词（Hotwords）**
  - [x] 热词列表数据结构：`[HotwordEntry]`，持久化到 `hotwords.json` — `Services/HotwordStore.swift`
  - [x] ASR 请求中携带热词参数（Volcano bigmodel 接口 `context.hotwords`）— `Session/RecognitionSession.swift`
  - [x] 设置界面：热词管理面板（增删改，支持批量导入）— `UI/MainWindow/MainPanelView.swift` → `HotwordManagerView`
  - [x] 热词变更后下次识别立即生效 — 每次录音前动态加载 `HotwordStore.shared.getAllWords()`

- [ ] **片段替换（Snippets）**
  - [ ] 片段规则数据结构：`[(trigger: String, replacement: String)]`，持久化到 config.json
  - [ ] LLM 处理后、粘贴前执行文本替换
  - [ ] 设置界面：片段规则管理面板（增删改）
  - [ ] 支持大小写不敏感匹配

- [x] **自动学习修正**
  - [x] 定义"修正"：用户编辑历史记录文本，捕获 word-level diff — `Services/WordDiff.swift`
  - [x] 修正记录持久化：热词自动存入 `hotwords.json`，source 标记为 `.learned` — `Services/HotwordStore.swift`
  - [x] LLM 验证修正合理性 — `HotwordStore.addWithLLMValidation()`
  - [x] 历史记录中可查看/管理学习到的修正 — 编辑按钮 + 紫色 sparkle 标记

---

## 三、LLM 语音模式

- [ ] **模式枚举**
  - [ ] 定义 `LLMMode`：`.quick`（不走 LLM）、`.correct`（纠错）、`.polish`（润色）、`.translate`（翻译）、`.custom`（自定义模板）
  - [ ] 模式状态持久化到 UserDefaults

- [ ] **语音润色（Voice Polish）**
  - [ ] 润色 Prompt：去除语气词、整理口语化表达、书面化输出
  - [ ] 润色模式下展示预览，用户可选择接受/放弃/编辑后再粘贴
  - [ ] 设置界面中可编辑润色 Prompt

- [ ] **翻译模式**
  - [ ] 支持方向选择：中文→英文 / 英文→中文
  - [ ] 翻译 Prompt 模板，目标语言可配置
  - [ ] 可与润色组合使用（先翻译再润色，或反过来）

- [ ] **自定义 Prompt 模板**
  - [ ] 内置模板：纠错、润色、翻译（不可删除，可复制后修改）
  - [ ] 用户自定义模板：`(name: String, prompt: String)`，持久化到 config.json
  - [ ] 模板变量支持：`{text}`（识别文本）、`{clipboard}`（剪贴板内容）、`{selected}`（当前选中文本）
  - [ ] 设置界面：模板管理（增删改，预览变量替换效果）
  - [ ] 快捷键或菜单切换当前使用的模式

---

## 四、数据管理

- [x] **历史记录**
  - [x] 记录数据结构：`(rawText, optimizedText, mode, timestamp, duration)` — `Services/HistoryStore.swift`
  - [x] 每次识别完成后自动保存（存入本地 JSON 文件）— `AppState.saveHistoryRecord()`
  - [x] 历史列表界面：按时间倒序，支持滚动加载 — `MainPanelView` → `historySection`
  - [x] 支持关键词搜索 — `HistoryStore.search()` + `MainPanelView` 搜索栏
  - [x] 单条记录操作：复制文本、重新插入光标位置、删除 — `HistoryRecordRow`
  - [x] 导出为 CSV（全部或筛选后）— `HistoryStore.exportCSV()`
  - [x] 历史记录上限配置（最多保留 1000 条，超出自动清理最早的）— `HistoryStore.maxRecords`
