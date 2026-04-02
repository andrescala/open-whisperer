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

    var onQuit: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()

        setupMenu()
        updateState(.loading)
        statusItem.menu = menu
    }

    private func setupMenu() {
        let titleItem = NSMenuItem(title: "Whisperer", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: "Hotkey: Option + Space", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Whisperer", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func updateState(_ state: AppState) {
        guard let button = statusItem.button else { return }

        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisperer - Ready")
            button.image?.isTemplate = true
            updateStatusText("Ready")
        case .recording:
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemCyan])
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
            firstItem.title = "Whisperer — \(text)"
        }
    }

    @objc private func quitAction() {
        onQuit?()
        NSApplication.shared.terminate(nil)
    }
}
