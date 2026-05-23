# OpenType

macOS menu-bar voice input tool. Press a hotkey, speak, and the transcribed text is automatically pasted into whatever app you're using.

**Cloud ASR via [Volcano Engine](https://www.volcengine.com/product/seed-asr)** (火山引擎流式语音识别大模型). No local models, no Python runtime.

## Features

- **Streaming recognition** — real-time partial results as you speak
- **Volcano Engine large-model ASR** — high-accuracy Chinese + English
- **LLM text post-processing** — remove filler words, fix grammar, translate (TODO)
- **Custom hotwords** — improve recognition of proper nouns
- **Menu-bar app** — lightweight, no Dock icon
- **Global hotkey** — works in any application
- **Auto-paste** — text injected directly into the active text field

## Requirements

- macOS 14+ (Sonoma)
- Volcano Engine account with App ID + Access Token
- Microphone permission
- Accessibility permission (for global hotkey + text injection)

## Build

```bash
swift build
swift run OpenType
```

## Configuration

1. Sign up at [volcengine.com](https://www.volcengine.com)
2. Enable the **流式语音识别大模型** (Streaming ASR Large Model) service
3. Create an App ID and Access Token
4. Enter credentials in OpenType Settings → 语音识别

## Project Structure

```
Sources/OpenType/
├── Protocol/     Volcano Engine binary frame protocol
├── ASR/          ASR abstraction + Volcano streaming client
├── Audio/        AVFoundation 16 kHz mono capture
├── Session/      Core state machine (record → ASR → inject)
├── Injection/    Clipboard save/restore + Cmd+V
├── LLM/          (TODO) LLM text post-processing
├── Input/        (TODO) Global hotkey manager
├── Services/     (TODO) Credential storage
└── UI/           Settings, floating bar, menu bar
```

## Roadmap

- [ ] Global hotkey manager (press-and-hold activation)
- [ ] Floating overlay during recording
- [ ] LLM text post-processing (OpenAI-compatible)
- [ ] Custom vocabulary / hotword management
- [ ] History view
- [ ] Settings UI with credential input
- [ ] App bundle + DMG packaging + code signing
- [ ] Auto-update

## License

MIT
