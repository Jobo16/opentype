# OpenType — Development Guide

## Overview

macOS menu-bar voice input tool. Press a hotkey → speak → text is transcribed (cloud ASR via Volcano Engine) → optionally polished by DeepSeek LLM → automatically pasted into the active app.

**Cloud-only**: no local STT engines, no Python dependencies. The sole ASR backend is Volcano Engine (火山引擎) streaming large-model ASR.

## Build & Run

```bash
# Debug build
swift build

# Run
swift run OpenType
```

Requires macOS 14+ (Sonoma). Xcode 15+ recommended for IDE support.

## Build & Package

```bash
swift build -c release
# Binary at .build/release/OpenType

# Package as .app bundle
APP_DIR="build/OpenType.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/release/OpenType "$APP_DIR/Contents/MacOS/OpenType"
# See build/OpenType.app/Contents/Info.plist for bundle config
```

## Project Structure

```
Sources/OpenType/
├── OpenTypeApp.swift              # @main entry (MenuBarExtra app)
├── AppState.swift                 # @MainActor ObservableObject — central coordinator
├── Protocol/                      # Volcano Engine binary frame protocol
│   ├── VolcHeader.swift           # 4-byte header encode/decode
│   ├── VolcProtocol.swift         # Full message encode/decode, gzip
│   └── VolcProtocolError.swift
├── ASR/                           # ASR abstraction layer
│   ├── ASRProvider.swift          # Provider enum, CredentialField, ASRProviderConfig protocol
│   ├── ASRProviderRegistry.swift  # Provider → client factory mapping
│   ├── SpeechRecognizer.swift     # Core protocol + RecognitionEvent/Transcript types
│   ├── VolcanoASRConfig.swift     # Volcano credential config
│   └── VolcASRClient.swift        # Streaming WebSocket client (bigmodel_async)
├── Audio/
│   └── AudioCaptureEngine.swift   # AVFoundation 16 kHz mono capture
├── Session/
│   └── RecognitionSession.swift   # Core state machine: record → ASR → LLM → inject
├── Injection/
│   └── TextInjectionEngine.swift  # Clipboard save/restore + Cmd+V
├── LLM/                           # LLM text post-processing
│   ├── LLMClient.swift            # Protocol + LLMConfig struct
│   ├── DeepSeekClient.swift       # DeepSeek API client (OpenAI-compatible)
│   └── PromptBuilder.swift        # System prompt for text correction
├── Input/
│   └── HotkeyManager.swift        # Global hotkey via NSEvent monitors
├── Services/
│   └── CredentialService.swift    # JSON credential storage (ASR + LLM)
└── UI/
    ├── MenuBarView.swift           # Menu bar dropdown menu
    ├── HotKeyField.swift           # NSViewRepresentable hotkey capture field
    ├── FloatingBar/                # Transparent overlay during recording
    │   ├── FloatingBarController.swift  # NSPanel + generation counter
    │   └── FloatingBarView.swift
    ├── MainWindow/                 # Unified control panel window
    │   ├── MainPanelView.swift     # Record + Settings tabs
    │   └── MainWindowController.swift  # NSWindow management
    └── Settings/
        └── SettingsView.swift      # Standalone settings (backup entry)
```

## Pipeline Flow

```
HotkeyManager (NSEvent global/local monitor)
    ↓ toggle
RecognitionSession.start()
    ↓
AudioCaptureEngine.start()
    ↓ 16kHz mono PCM chunks
VolcASRClient.connect() → WebSocket → stream audio
    ↓ receive partials + final
RecognitionSession (LLM step)
    ↓ if LLM enabled
DeepSeekClient.chat(systemPrompt, rawText)
    ↓ optimized text
TextInjectionEngine.inject(text)
    ↓ clipboard + Cmd+V
Done
```

## ASR Architecture

Cloud-only, Volcano Engine WebSocket streaming ASR.

### Connection Lifecycle

1. `RecognitionSession.start()` → starts `AudioCaptureEngine`
2. `VolcASRClient.connect()` → opens WebSocket to `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`
3. Sends `full_client_request` (JSON in binary frame header)
4. Audio chunks sent as `audioOnlyRequest` binary frames (200 ms / 3200 samples each)
5. `endAudio()` sends final empty packet with `lastPacketNoSequence` flag
6. Client receives `asyncFinal` response with authoritative text
7. If LLM enabled → `DeepSeekClient` processes text
8. `TextInjectionEngine` pastes into active app

### Binary Frame Protocol

4-byte header: `[version|headerSize] [msgType|flags] [serialization|compression] [reserved]`

- `fullClientRequest` (0x01): initial JSON payload with audio params + user config
- `audioOnlyRequest` (0x02): raw PCM audio chunks
- `serverResponse` (0x09): JSON with `result.text` and `result.utterances[].definite`
- `serverError` (0x0F): error or session-complete signal

### Auth Headers (no HMAC signing needed)

```
X-Api-App-Key:     {appKey / App ID}
X-Api-Access-Key:  {accessKey / Access Token}
X-Api-Resource-Id: volc.seedasr.sauc.duration (or volc.bigasr.sauc.duration)
X-Api-Connect-Id:  {UUID}
```

**Important**: `resourceId` value `"auto"` must be resolved to `"volc.seedasr.sauc.duration"` before sending — the server does not accept the literal string `"auto"`.

### Transcript Assembly

The server emits partial results (`definite: false`) and final segments (`definite: true`).
`VolcASRClient` tracks:
- `localConfirmedSegments`: server-confirmed + locally promoted dropped partials
- `partialText`: current in-progress utterance
- Display text = `confirmedSegments.joined() + partialText`

Dropped-partial detection: when the server starts a new utterance without confirming the previous partial (LCP ratio < 0.5), the old partial is promoted to a local confirmed segment.

## LLM Post-Processing

Optional text optimization via DeepSeek API (OpenAI-compatible).

### Configuration

- API Key stored in JSON config (`~/Library/Application Support/OpenType/config.json`)
- Default model: `deepseek-v4-flash` (fast, low-latency)
- Toggle on/off in Settings → LLM

### System Prompt

The prompt instructs the LLM to:
1. Remove fillers (呃/啊/嗯/那个/就是)
2. Handle self-corrections (only keep final version)
3. Fix homophones based on context
4. Add punctuation
5. Format numbers (两千三百 → 2300)
6. Restore English words from phonetic transcription (瑞嗯特 → React)

**Boundary**: Never add content the speaker didn't say.

### Fallback

If LLM fails (network error, timeout, API error), raw ASR text is used. The pipeline never blocks on LLM failure.

## Audio Pipeline

```
AVAudioEngine (system default input, native sample rate)
    ↓ AVAudioConverter
16 kHz mono Float32 PCM
    ↓ 200 ms chunks
VolcASRClient.sendAudio(Data)
```

Audio level metering: RMS computed on last 800 samples (~50 ms), scaled 0…1.

## Permissions Required

| Permission | Purpose |
|---|---|
| Microphone | Audio capture |
| Accessibility | Text injection into other apps (Cmd+V) |

Note: Global hotkey uses `NSEvent.addGlobalMonitorForEvents` which does NOT require Accessibility permission (unlike CGEvent taps).

## Credential Storage

All credentials stored in JSON at `~/Library/Application Support/OpenType/config.json`:
- ASR credentials (App ID, Access Token, resource ID)
- LLM credentials (API Key, model, API base URL)

UserDefaults used for:
- Hotkey string (`ot_hotkey`)
- LLM enabled flag (`ot_llm_enabled`)

## Key Design Decisions

1. **Cloud-only ASR**: No local STT, no Python runtime. Simplifies deployment dramatically.
2. **Volcano Engine only (v1)**: Single ASR provider for now; architecture supports adding more.
3. **Unified main window**: Single window with Record/Settings tabs — no separate Settings scene.
4. **Swift-only**: No Rust FFI, no C bridges. Pure Swift + AVFoundation + AppKit.
5. **Actor-based concurrency**: `RecognitionSession`, `AudioCaptureEngine`, `VolcASRClient` are all actors for thread safety.
6. **ObservableObject (not @Observable)**: AppState uses `ObservableObject` for compatibility with AppKit's `NSHostingView`.
7. **NSEvent monitors (not CGEvent taps)**: More reliable for unsigned apps, no Accessibility permission needed for hotkey monitoring.
8. **JSON-only storage**: No Keychain — avoids permission prompts for unsigned apps.
