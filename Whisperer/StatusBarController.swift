import Cocoa

enum AppState {
    case idle
    case recording
    case transcribing
    case loading
    case error(String)
}

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private var translateItem: NSMenuItem!

    var onQuit: (() -> Void)?
    var onTranslateToggled: ((Bool) -> Void)?

    var translateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "translateToEnglish") }
        set {
            UserDefaults.standard.set(newValue, forKey: "translateToEnglish")
            translateItem.state = newValue ? .on : .off
        }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()

        setupMenu()
        updateState(.loading)
        statusItem.menu = menu
    }

    private func setupMenu() {
        let titleItem = NSMenuItem(title: "AC Voice", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: "Hotkey: Option + Space", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        menu.addItem(NSMenuItem.separator())

        translateItem = NSMenuItem(title: "Translate to English", action: #selector(toggleTranslate), keyEquivalent: "")
        translateItem.target = self
        translateItem.state = translateEnabled ? .on : .off
        menu.addItem(translateItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About AC Voice", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit AC Voice", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "AC Voice"
        alert.informativeText = """
            Local, offline voice-to-text for macOS.
            Hold Option + Space to dictate — text appears at your cursor in any app.

            ── Features ──────────────────────────
            • 100% offline — audio never leaves your Mac
            • Powered by OpenAI Whisper large-v3 via Neural Engine (WhisperKit)
            • Real-time FFT spectrum visualizer during recording
            • Translate speech to English from any language
            • Works in any app — no integration required

            ── Open Source Libraries ─────────────
            • WhisperKit (argmaxinc) — CoreML/Neural Engine Whisper inference
            • OpenAI Whisper large-v3 — state-of-the-art speech recognition model
            • Apple Accelerate / vDSP — real-time FFT frequency analysis
            • AVFoundation — microphone capture & audio conversion
            • CoreGraphics CGEvent — system-wide hotkey detection

            ── Created by ────────────────────────
            Claude Code (Sonnet 4.6 & Opus 4.6)
            & Andres Cala — andres.cala@ac-labs.com
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Close")

        if let icon = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
            alert.icon = icon.withSymbolConfiguration(config)
        }

        alert.runModal()
    }

    @objc private func toggleTranslate() {
        translateEnabled = !translateEnabled
        onTranslateToggled?(translateEnabled)
    }

    func updateState(_ state: AppState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AC Voice - Ready")
            button.image?.isTemplate = true
            updateStatusText("Ready")
        case .recording:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(config)
            updateStatusText("Recording...")
        case .transcribing:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            button.image = NSImage(systemSymbolName: "waveform.badge.magnifyingglass", accessibilityDescription: "Transcribing")?
                .withSymbolConfiguration(config)
            updateStatusText("Transcribing...")
        case .loading:
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Loading")
            button.image?.isTemplate = true
            updateStatusText("Loading model...")
        case .error(let message):
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
            button.image?.isTemplate = true
            updateStatusText("Error: \(message)")
        }
    }

    func updateDownloadProgress(_ progress: Double) {
        updateStatusText("Downloading model: \(Int(progress * 100))%")
    }

    private func updateStatusText(_ text: String) {
        if let firstItem = menu.items.first {
            firstItem.title = "AC Voice — \(text)"
        }
    }

    @objc private func quitAction() {
        onQuit?()
        NSApplication.shared.terminate(nil)
    }
}
