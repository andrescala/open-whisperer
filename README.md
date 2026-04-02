# Open Whisperer

**Local, offline voice-to-text for macOS.** Hold Option+Space, speak, release — text appears at your cursor. Powered by Whisper AI, runs entirely on-device. No cloud, no accounts, no subscription.

Built with [whisper.cpp](https://github.com/ggerganov/whisper.cpp) via [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) and native macOS APIs.

---

## How It Works

1. **Hold Option+Space** — a floating pill with a reactive waveform appears near your cursor and recording begins
2. **Speak** — the waveform bars respond to your voice in real-time (quiet = low bars, loud = tall bars)
3. **Release Option+Space** — the waveform switches to a spinning indicator while Whisper transcribes your audio locally
4. **Text appears** at your cursor in whatever app you're using — VS Code, Slack, Safari, Terminal, Notes, anything

The entire pipeline runs on your Mac. Audio never leaves your machine.

---

## Performance

On Apple Silicon, transcription is fast:

| Speech Duration | Transcription Time (approx.) |
|----------------|------------------------------|
| 5 seconds | ~1 second |
| 15 seconds | ~2-3 seconds |
| 30 seconds | ~4-6 seconds |

The app uses the Whisper `small.en` model (~488MB) by default, which provides great accuracy for English. It downloads automatically on first launch and is cached locally at `~/Library/Application Support/Whisperer/Models/`.

---

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon** recommended (M1/M2/M3/M4) — Intel Macs work but transcription is slower
- **Xcode** (with command line tools installed)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — install with `brew install xcodegen`

---

## Build & Run

### Option 1: Command Line

```bash
# Clone the repo
git clone git@github.com:andrescala/open-whisperer.git
cd open-whisperer

# Install xcodegen if you don't have it
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Build (Release for best transcription performance)
xcodebuild -project Whisperer.xcodeproj -scheme Whisperer -configuration Release build

# Run
open ~/Library/Developer/Xcode/DerivedData/Whisperer-*/Build/Products/Release/Whisperer.app
```

### Option 2: Xcode

```bash
git clone git@github.com:andrescala/open-whisperer.git
cd open-whisperer
xcodegen generate
open Whisperer.xcodeproj
```

Then press **Cmd+R** to build and run.

> **Note:** whisper.cpp runs 10-20x slower in Debug builds. Use the **Release** scheme when testing transcription performance.

---

## First Launch Setup

On first launch, three things happen:

### 1. Model Download
The Whisper `base.en` model (~148MB) downloads from HuggingFace. Progress is shown in the menu bar. This only happens once — the model is cached for all future launches.

### 2. Microphone Permission
macOS will prompt you to grant microphone access. Click **Allow**. The app needs this to record your voice.

### 3. Accessibility Permission
The app needs Accessibility access to register the global hotkey (Option+Space) and to inject text at your cursor. System Settings will open automatically — find **Whisperer** in the Accessibility list and toggle it on.

The app detects the permission automatically and activates as soon as you grant it. No restart needed.

---

## Usage

Once set up, Whisperer lives in your **menu bar** as a waveform icon (no dock icon, no windows).

| Action | What Happens |
|--------|-------------|
| **Hold Option+Space** | Recording starts, waveform overlay appears near cursor |
| **Release Option+Space** | Recording stops, transcription begins (spinner overlay) |
| **Transcription completes** | Text is pasted at your cursor, overlay disappears |
| **Click menu bar icon** | Shows status and quit option |

The text injection works by temporarily using your clipboard (the previous clipboard contents are saved and restored after pasting).

---

## Architecture

```
                    ┌─────────────────┐
                    │   HotkeyManager │  CGEvent tap (Option+Space)
                    │   (keyDown/Up)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │   AppDelegate   │  Coordinator
                    └──┬──────────┬───┘
          keyDown      │          │      keyUp
       ┌───────────────▼┐   ┌────▼──────────────┐
       │  AudioRecorder  │   │ AudioRecorder.stop │
       │  .startRecording│   │ returns [Float]    │
       │  (16kHz mono)   │   └────────┬───────────┘
       └───────┬─────────┘            │
               │                ┌─────▼──────────────┐
               │ audio levels   │ TranscriptionEngine │  SwiftWhisper
               │                │ .transcribe(frames) │  (whisper.cpp)
       ┌───────▼─────────┐     └─────────┬───────────┘
       │  OverlayWindow  │               │
       │  (waveform bars)│         ┌─────▼──────┐
       └─────────────────┘         │ TextInjector│  Clipboard + Cmd+V
                                   └─────────────┘
```

### Tech Stack

| Component | Technology | What It Does |
|-----------|-----------|--------------|
| Speech-to-text | [whisper.cpp](https://github.com/ggerganov/whisper.cpp) via [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) | Transcribes audio to text using OpenAI's Whisper model, optimized for Apple Silicon |
| Audio capture | AVAudioEngine + AVAudioConverter | Records microphone at native sample rate, converts to 16kHz mono float32 (what Whisper expects) |
| Global hotkey | CGEvent tap | Listens for Option+Space system-wide, even when Whisperer isn't in focus |
| Text injection | NSPasteboard + CGEvent | Saves clipboard, sets transcribed text, simulates Cmd+V paste, restores clipboard |
| Menu bar UI | NSStatusBar | Waveform icon with state changes (idle/recording/transcribing/error) |
| Recording overlay | NSWindow (borderless, floating) | Pill-shaped widget with reactive waveform bars that follows the cursor |
| Transcribing overlay | NSWindow (borderless, floating) | Same pill, switches to spinning dots while processing |
| Model management | URLSession | Downloads GGML model from HuggingFace on first launch, caches locally |

---

## Project Structure

```
open-whisperer/
├── project.yml                    # XcodeGen config (generates the .xcodeproj)
├── Whisperer/
│   ├── main.swift                 # App entry point
│   ├── AppDelegate.swift          # Coordinator — wires all components, manages lifecycle
│   ├── StatusBarController.swift  # Menu bar icon with state-dependent SF Symbols
│   ├── AudioRecorder.swift        # AVAudioEngine → 16kHz mono float32 + audio level callback
│   ├── TranscriptionEngine.swift  # SwiftWhisper model loading and async transcription
│   ├── TextInjector.swift         # Clipboard save → set text → Cmd+V paste → clipboard restore
│   ├── HotkeyManager.swift        # CGEvent tap for Option+Space hold/release detection
│   ├── ModelManager.swift         # Downloads and caches GGML Whisper model files
│   ├── OverlayWindow.swift        # Floating pill overlay (waveform + spinner modes)
│   ├── WhispererError.swift       # Error type definitions
│   ├── Info.plist                 # LSUIElement (no dock icon), mic usage description
│   └── Whisperer.entitlements     # Audio input entitlement (no sandbox)
└── Whisperer.xcodeproj/           # Generated by xcodegen (can be regenerated)
```

---

## Privacy & Security

- **100% local** — after the initial model download, there are zero network calls. Ever.
- **No telemetry, no analytics, no tracking, no accounts**
- **Audio is never saved to disk** — it's processed in memory and discarded after transcription
- **Clipboard is preserved** — previous clipboard contents are saved before pasting and restored after
- **No sandbox** — the app requires CGEvent taps for the global hotkey and text injection, which are incompatible with macOS App Sandbox. This means the app must be run outside of the Mac App Store.
- **Permissions are minimal** — only Microphone (to record) and Accessibility (for the hotkey and paste simulation)

---

## Changing the Whisper Model

The default model is `small.en` (~488MB). To switch to a different model, edit `ModelManager.swift` and change two values:

```swift
static let modelFileName = "ggml-small.en.bin"      // ← change filename
static let modelDownloadURL = URL(string:
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin?download=true"  // ← change URL
)!
```

Available models:

| Model | Filename | Size | Speed (30s, Apple Silicon) | Accuracy |
|-------|----------|------|---------------------------|----------|
| tiny.en | `ggml-tiny.en.bin` | 75 MB | ~1 sec | Good |
| base.en | `ggml-base.en.bin` | 148 MB | ~2 sec | Better |
| **small.en** | **`ggml-small.en.bin`** | **488 MB** | **~4-6 sec** | **Great (default)** |
| medium.en | `ggml-medium.en.bin` | 1.5 GB | ~8-12 sec | Excellent |

After changing the model, rebuild and delete the old cached model:

```bash
rm -rf ~/Library/Application\ Support/Whisperer/Models/
xcodebuild -project Whisperer.xcodeproj -scheme Whisperer -configuration Release build
```

The new model will download automatically on next launch.

> **Tip:** For machines with 8GB+ RAM and Apple Silicon, `small.en` is the sweet spot. Use `base.en` if you prefer faster responses over accuracy, or `medium.en` if accuracy is critical.

---

## Troubleshooting

### Option+Space doesn't work
- Check **System Settings > Privacy & Security > Accessibility** — Whisperer must be toggled on
- If you rebuilt the app, the Accessibility toggle may have reset (the code signature changed). Toggle it off and on again
- Check for conflicts with other apps that use Option+Space (Raycast, Alfred, Spotlight alternatives)

### Transcription is slow
- Make sure you're running a **Release** build, not Debug. Debug builds of whisper.cpp are 10-20x slower
- On Intel Macs, transcription is significantly slower than on Apple Silicon

### App crashes on launch
- Ensure the Microphone usage description is present in Info.plist (regenerate with `xcodegen generate` if needed)
- Try resetting permissions: `tccutil reset Microphone com.crutech.whisperer`

### Text doesn't appear at cursor
- Check that the target app supports Cmd+V paste
- Some apps with custom input handling may not respond to simulated keyboard events

---

## Future Ideas

- AI post-processing via Claude or local LLM to clean up grammar and formatting
- Custom vocabulary biasing for domain-specific terms
- Transcription history with search
- Configurable hotkey
- Voice commands ("open Safari", "new paragraph")

---

## Credits

- [OpenAI Whisper](https://github.com/openai/whisper) — the speech recognition model
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — high-performance C++ port by Georgi Gerganov
- [SwiftWhisper](https://github.com/exPHAT/SwiftWhisper) — Swift wrapper with async/await support
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — Xcode project generation from YAML

---

## License

[MIT](LICENSE) — free to use, modify, and distribute.
