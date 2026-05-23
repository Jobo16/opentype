# OpenType — Development Guide

## Overview

macOS menu-bar voice input tool. Press a hotkey → speak → text is transcribed (cloud ASR via Volcano Engine) → optionally polished by an LLM → automatically pasted into the active app.

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
```

Packaging as `.app` bundle + DMG is TODO (see `scripts/`).

## Project Structure

```
Sources/OpenType/
├── OpenTypeApp.swift          # @main entry point (menu-bar-only app)
├── Protocol/                  # Volcano Engine binary frame protocol
│   ├── VolcHeader.swift       # 4-byte header encode/decode
│   ├── VolcProtocol.swift     # Full message encode/decode, gzip
│   └── VolcProtocolError.swift
├── ASR/                       # ASR abstraction layer
│   ├── ASRProvider.swift      # Provider enum, CredentialField, ASRProviderConfig protocol
│   ├── ASRProviderRegistry.swift  # Provider → client factory mapping
│   ├── SpeechRecognizer.swift     # Core protocol + RecognitionEvent/Transcript types
│   ├── VolcanoASRConfig.swift     # Volcano credential config
│   └── VolcASRClient.swift        # Streaming WebSocket client (bigmodel_async)
├── Audio/
│   └── AudioCaptureEngine.swift   # AVFoundation 16 kHz mono capture
├── Session/
│   └── RecognitionSession.swift   # Core state machine: record → ASR → inject
├── Injection/
│   └── TextInjectionEngine.swift  # Clipboard save/restore + Cmd+V
├── LLM/                        # (TODO) LLM text post-processing
├── Input/                      # (TODO) Global hotkey manager
├── Services/                   # (TODO) Credential storage, hotword storage
└── UI/
    ├── MenuBarView.swift       # System tray menu
    ├── FloatingBar/            # Transparent overlay during recording
    └── Settings/               # Settings tabs (General, ASR, LLM)
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
7. `RecognitionSession` passes text to `TextInjectionEngine`

### Binary Frame Protocol

4-byte header: `[version|headerSize] [msgType|flags] [serialization|compression] [reserved]`

- `fullClientRequest` (0x01): initial JSON payload with audio params + user config
- `audioOnlyRequest` (0x02): raw PCM audio chunks
- `serverResponse` (0x09): JSON with `result.text` and `result.utterances[].definite`
- `serverError` (0x0F): error or session-complete signal

### Auth Headers (no HMAC signing needed)

```
X-Api-App-Key:    {appKey / App ID}
X-Api-Access-Key: {accessKey / Access Token}
X-Api-Resource-Id: volc.seedasr.sauc.duration (or volc.bigasr.sauc.duration)
X-Api-Connect-Id:  {UUID}
```

### Transcript Assembly

The server emits partial results (`definite: false`) and final segments (`definite: true`).
`VolcASRClient` tracks:
- `localConfirmedSegments`: server-confirmed + locally promoted dropped partials
- `partialText`: current in-progress utterance
- Display text = `confirmedSegments.joined() + partialText`

Dropped-partial detection: when the server starts a new utterance without confirming the previous partial (LCP ratio < 0.5), the old partial is promoted to a local confirmed segment.

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
| Accessibility | Global hotkey listening + text injection into other apps |

## Credential Storage

- **Secure fields** (API keys): macOS Keychain
- **Non-secure fields** (model ID, etc.): `~/Library/Application Support/OpenType/config.json`

Settings UI is the only supported configuration method (GUI-launched apps cannot read shell env vars).

## Key Design Decisions

1. **Cloud-only ASR**: No local STT, no Python runtime. Simplifies deployment dramatically.
2. **Volcano Engine only (v1)**: Single ASR provider for now; architecture supports adding more.
3. **Menu-bar app**: No Dock icon, no main window. Settings via menu-bar dropdown.
4. **Swift-only**: No Rust FFI, no C bridges. Pure Swift + AVFoundation.
5. **Actor-based concurrency**: `RecognitionSession`, `AudioCaptureEngine`, `VolcASRClient` are all actors for thread safety.
