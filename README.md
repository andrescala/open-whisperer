# AC Voice

**Local, offline voice-to-text for macOS.** Hold `Option + Space`, speak, release — transcribed text appears at your cursor in any app. Powered by OpenAI Whisper running entirely on-device via Apple's Neural Engine. No cloud, no accounts, no subscription, no data ever leaving your machine.

---

## Demo

| State | What you see |
|-------|-------------|
| **Idle** | Waveform icon in menu bar |
| **Recording** | Orange waveform icon + floating pill with 16-bar FFT spectrum analyzer |
| **Transcribing** | Spinning arc overlay while Whisper processes locally |
| **Done** | Text injected at cursor, overlay disappears |

---

## Features

- **100% offline** — after the first model download, zero network calls ever
- **Works in any app** — VS Code, Slack, Safari, Terminal, Notes, anything that accepts keyboard input
- **Real-time FFT spectrum visualizer** — 16 frequency bands react to actual microphone input using Apple's Accelerate framework
- **Translate to English** — toggle in the menu bar to translate from any language while speaking
- **Clipboard-safe text injection** — saves and restores previous clipboard contents around paste
- **No dock icon** — lives entirely in the menu bar (LSUIElement)
- **Automatic permission polling** — detects Accessibility grant without requiring a restart
- **Self-signed cert support** — stable code signature means TCC permission survives rebuilds

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **macOS** | 14.0 Sonoma or later |
| **Hardware** | See table below |
| **Xcode** | 15+ with Command Line Tools (`xcode-select --install`) |
| **Homebrew** | For installing XcodeGen |
| **XcodeGen** | `brew install xcodegen` |

### Recommended Hardware

| Tier | Hardware | Experience |
|------|----------|-----------|
| ✅ **Optimal** | M2 / M3 / M4 (any) with 16 GB+ RAM | Near-instant transcription via Neural Engine; large-v3 model loads in ~3s |
| ✅ **Great** | M1 (any) with 16 GB RAM | Excellent; slightly slower model load, transcription still <2s for 30s audio |
| ⚠️ **Acceptable** | M1 with 8 GB RAM | Works well with `large-v3`; may feel slow if many other apps compete for RAM |
| ⚠️ **Usable** | Intel Mac (2019+) with 16 GB RAM | CPU-only inference; transcription takes 3–8x longer — consider `openai_whisper-small` |
| ❌ **Not recommended** | Intel with 8 GB RAM | Very slow; use `openai_whisper-base` and expect 10+ second waits |

> The `openai_whisper-large-v3` model (~1.5 GB) needs to fit comfortably in memory alongside the OS. On Apple Silicon, it runs on the Neural Engine and doesn't compete with CPU/GPU workloads.

---

## Installation

### Quick Install (recommended)

```bash
# 1. Clone
git clone https://github.com/andrescala/ac-voice.git
cd ac-voice

# 2. Install XcodeGen if you don't have it
brew install xcodegen

# 3. Generate the Xcode project
xcodegen generate

# 4. (Optional) Create a stable self-signed cert so permissions survive rebuilds
make cert

# 5. Build, install to /Applications, and launch
make install
```

`make install` will:
- Build in Release configuration
- Copy the app to `/Applications/AC Voice.app`
- Sign it with your cert (or ad-hoc if none)
- Reset the Accessibility permission so macOS re-prompts cleanly
- Launch the app

### Manual Build via Xcode

```bash
git clone https://github.com/andrescala/ac-voice.git
cd ac-voice
xcodegen generate
open ACVoice.xcodeproj
```

Select the **Release** scheme and press `Cmd+R`.

> ⚠️ **Always use Release for transcription.** Debug builds run 10–20x slower.

---

## First Launch

### 1. Model Download (~1.5 GB)
The `openai_whisper-large-v3` model downloads automatically from HuggingFace on first launch and is cached at `~/Library/Caches/huggingface/`. This only happens once. The menu bar shows **"Loading model..."** during download.

### 2. Microphone Permission
macOS will prompt for microphone access. Click **Allow**.

### 3. Accessibility Permission
The app needs Accessibility access to:
- Register the global `Option + Space` hotkey (via CGEvent tap)
- Inject text at your cursor (via simulated Cmd+V)

System Settings opens automatically — find **AC Voice** in the Accessibility list and enable it. No restart needed; the app polls for the permission and activates instantly.

---

## Usage

Once set up, AC Voice lives in the **menu bar** with a waveform icon.

| Action | Result |
|--------|--------|
| **Hold `Option + Space`** | Recording starts, orange FFT spectrum pill appears near cursor |
| **Speak** | Bars react to your voice frequencies in real time |
| **Release `Option + Space`** | Recording stops, arc spinner appears during transcription |
| **Transcription complete** | Text pasted at cursor, overlay disappears |
| **Click menu bar icon** | Status, Translate toggle, About, Quit |

### Translate to English
Enable **Translate to English** in the menu bar dropdown to have AC Voice translate your speech into English, regardless of what language you speak. Setting persists across launches.

---

## Makefile Commands

```bash
make install          # Build → install to /Applications → sign → launch
make cert             # Create 'AC Voice Dev' self-signed cert (run once)
make reset-permissions  # Reset Accessibility TCC entry if permission gets stuck
```

---

## Architecture

```
HotkeyManager (Option+Space keyDown)
    └──▶ AppDelegate.startDictation()
              └──▶ AudioRecorder.startRecording()
                        └──▶ onFrequencyBands callback
                                  └──▶ OverlayWindow.updateFrequencyBands()  (FFT bars)

HotkeyManager (Option+Space keyUp)
    └──▶ AppDelegate.stopDictation()
              ├──▶ AudioRecorder.stopRecording() → [Float] (16kHz mono PCM)
              ├──▶ OverlayWindow.show(mode: .transcribing)  (arc spinner)
              ├──▶ TranscriptionEngine.transcribe(frames:translate:) → String
              └──▶ TextInjector.inject(text)
```

---

## Project Structure

```
whisperer-open/
├── project.yml                    # XcodeGen config — source of truth for the Xcode project
├── Makefile                       # Build, cert, and permission reset helpers
├── install.sh                     # Full build → install → sign → launch pipeline
├── ACVoice.xcodeproj/             # Generated by xcodegen (safe to regenerate)
└── Whisperer/
    ├── main.swift                 # NSApplication entry point
    ├── AppDelegate.swift          # Central coordinator — wires all components, manages lifecycle
    ├── StatusBarController.swift  # Menu bar icon, state-dependent SF Symbols, translate toggle
    ├── AudioRecorder.swift        # AVAudioEngine tap → 16kHz mono float32 + real-time FFT bands
    ├── TranscriptionEngine.swift  # WhisperKit model loading + async transcription
    ├── TextInjector.swift         # Clipboard save → set text → simulate Cmd+V → clipboard restore
    ├── HotkeyManager.swift        # CGEvent tap for Option+Space hold/release detection
    ├── OverlayWindow.swift        # Floating pill: 16-bar FFT spectrum (recording) + arc spinner (transcribing)
    ├── WhispererError.swift       # Typed error definitions
    ├── Info.plist                 # LSUIElement=true, NSMicrophoneUsageDescription
    └── ACVoice.entitlements       # com.apple.security.device.audio-input (no sandbox)
```

---

## Open Source Libraries & Models

### [WhisperKit](https://github.com/argmaxinc/WhisperKit) — argmaxinc
Swift framework that wraps OpenAI Whisper models compiled to CoreML, running on Apple's Neural Engine. Delivers 2–5x faster inference than CPU-based whisper.cpp on Apple Silicon. Handles model download, caching, and async transcription.

```swift
// Package dependency in project.yml:
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit.git
    from: 0.9.0
```

### [OpenAI Whisper large-v3](https://huggingface.co/openai/whisper-large-v3)
State-of-the-art multilingual speech recognition model. Supports 99+ languages. The `large-v3` variant used here achieves near-human accuracy on clean speech. Downloaded automatically from HuggingFace (~1.5 GB, cached after first run).

### Apple Accelerate / vDSP
Apple's high-performance SIMD math framework, used for the real-time FFT spectrum analysis:
- `vDSP_create_fftsetup` — 1024-point FFT setup
- `vDSP_hann_window` — Hann windowing to reduce spectral leakage
- `vDSP_fft_zrip` — forward FFT on each audio buffer
- `vDSP_zvabs` — magnitude extraction
- 16 log-scaled frequency bands mapped to the speech range (~80 Hz – 7 kHz)

### Apple AVFoundation
- `AVAudioEngine` — low-latency microphone tap at the system's native sample rate
- `AVAudioConverter` — downsample from native rate (e.g. 48kHz) to 16kHz mono float32 (Whisper's expected format)

### Apple CoreGraphics (CGEvent)
- Global event tap for `Option + Space` keyDown/keyUp — works system-wide, even when AC Voice is not focused
- Simulated `Cmd+V` keyboard event for text injection into the frontmost app

### Apple CVDisplayLink
Used inside `OverlayPillView` to drive waveform and spinner animations at the display's native refresh rate (typically 60 or 120 fps), synchronized with the screen rather than timer-based.

### Apple NSPasteboard
Clipboard management for text injection — saves all existing pasteboard types before overwriting, restores them 200ms after paste so the user's clipboard is preserved.

---

## Changing the Whisper Model

Edit `AppDelegate.swift` and change the model name passed to `loadModel`:

```swift
try await transcriptionEngine.loadModel(modelName: "openai_whisper-large-v3")
```

Available models (all auto-downloaded from HuggingFace):

| Model | Size | Speed on M-series (30s audio) | Notes |
|-------|------|-------------------------------|-------|
| `openai_whisper-tiny` | ~75 MB | ~0.2s | Fastest, lowest accuracy |
| `openai_whisper-base` | ~145 MB | ~0.4s | Good for quick use |
| `openai_whisper-small` | ~488 MB | ~0.7s | Better accuracy |
| `openai_whisper-large-v3-v20240930_turbo` | ~800 MB | ~1.0s | Great speed/accuracy balance |
| `openai_whisper-large-v3` | ~1.5 GB | ~1.5s | **Default — highest accuracy** |

After changing the model, run `make install`. Clear the old cached model if switching:

```bash
rm -rf ~/Library/Caches/huggingface/
make install
```

---

## Troubleshooting

### `Option + Space` does nothing
1. Open **System Settings → Privacy & Security → Accessibility**
2. Find **AC Voice** and make sure it's toggled **on**
3. If the toggle is missing, run `make install` — it resets and re-prompts
4. Check for conflicts: Raycast, Alfred, and Spotlight can claim `Option + Space`

### Permissions keep resetting after rebuilding
Run `make cert` once to create a stable self-signed certificate. Ad-hoc signed apps get a new hash on every build, which invalidates TCC entries. A named certificate keeps the identity stable.

### App doesn't open / crashes silently
```bash
# Check crash logs
ls ~/Library/Logs/DiagnosticReports/ | grep -i acvoice

# Reset all permissions and reinstall
make reset-permissions
make install
```

### Transcription is very slow
- Use a **Release** build. Debug builds are 10–20x slower.
- On Intel Macs, transcription is CPU-only — consider `openai_whisper-base` or `openai_whisper-small`

### Text doesn't appear at cursor
- Some apps with fully custom input (e.g. game engines, VMs) don't respond to simulated Cmd+V
- Verify **Accessibility** permission is granted — text injection requires it

### Microphone sounds silent / transcription returns blank
```bash
tccutil reset Microphone com.crutech.acvoice
```
Then relaunch and grant mic permission again.

---

## Privacy & Security

| Concern | Answer |
|---------|--------|
| Does audio leave my Mac? | **Never.** After the initial model download, there are zero network connections |
| Is audio saved to disk? | **No.** Audio is processed in memory and discarded immediately after transcription |
| Is my clipboard read? | Only temporarily during injection — saved, overwritten with transcription, then restored |
| Why no App Sandbox? | CGEvent taps (global hotkey) and simulated keystrokes are incompatible with macOS sandbox |
| What permissions are needed? | Microphone (record voice) and Accessibility (hotkey + paste simulation) — nothing else |

---

## Future Ideas

- Configurable hotkey
- Transcription history with copy/search
- Custom vocabulary / prompt biasing for domain-specific terms
- AI post-processing (punctuation cleanup, formatting) via local LLM
- Voice commands ("new paragraph", "select all")
- Menu bar waveform animation while recording

---

## Credits

Built with:
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by [Argmax](https://www.argmaxinc.com/)
- [OpenAI Whisper](https://github.com/openai/whisper) — large-v3 model
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) by Yonas Kolb
- Apple Accelerate, AVFoundation, CoreGraphics, CVDisplayLink

Created by **Claude Code** (Sonnet 4.6 & Opus 4.6) & **Andres Cala** — [andres.cala@ac-labs.com](mailto:andres.cala@ac-labs.com)

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.
