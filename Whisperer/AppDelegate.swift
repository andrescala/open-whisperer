import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController!
    private var hotkeyManager: HotkeyManager!
    private var audioRecorder: AudioRecorder!
    private var transcriptionEngine: TranscriptionEngine!
    private var textInjector: TextInjector!

    private var overlayWindow: OverlayWindow!
    private var isProcessing = false
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        audioRecorder = AudioRecorder()
        transcriptionEngine = TranscriptionEngine()
        textInjector = TextInjector()

        hotkeyManager = HotkeyManager()
        overlayWindow = OverlayWindow()

        statusBarController.onQuit = { [weak self] in
            self?.accessibilityTimer?.invalidate()
            self?.hotkeyManager.stop()
        }

        statusBarController.onTranslateToggled = { enabled in
            print("[AC Voice] Translate to English: \(enabled)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task { await self.setup() }
        }
    }

    private func setup() async {
        await MainActor.run { statusBarController.updateState(.loading) }

        do {
            try await transcriptionEngine.loadModel(modelName: "openai_whisper-large-v3")
        } catch {
            print("[AC Voice] Setup failed: \(error)")
            await MainActor.run {
                statusBarController.updateState(.error("Model failed"))
                showAlert(title: "Model Loading Failed", message: "\(error)")
            }
            return
        }

        await MainActor.run { tryStartHotkey() }
    }

    private func tryStartHotkey() {
        hotkeyManager.onHotkeyDown = { [weak self] in self?.startDictation() }
        hotkeyManager.onHotkeyUp   = { [weak self] in self?.stopDictation() }

        let isTrusted = HotkeyManager.checkAccessibility(prompt: false)
        print("[AC Voice] AXIsProcessTrusted = \(isTrusted)")

        if isTrusted {
            let tapOK = hotkeyManager.start()
            print("[AC Voice] CGEvent.tapCreate succeeded = \(tapOK)")
            if tapOK {
                accessibilityTimer?.invalidate()
                accessibilityTimer = nil
                statusBarController.updateState(.idle)
                print("[AC Voice] Ready! Hold Option+Space to dictate.")
                return
            } else {
                statusBarController.updateState(.error("Tap failed"))
            }
        } else {
            statusBarController.updateState(.error("Grant Accessibility"))
            _ = HotkeyManager.checkAccessibility(prompt: true)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        print("[AC Voice] Waiting for Accessibility permission...")
        accessibilityTimer?.invalidate()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = HotkeyManager.checkAccessibility(prompt: false)
            print("[AC Voice] poll: trusted=\(trusted)")
            if trusted && self.hotkeyManager.start() {
                self.accessibilityTimer?.invalidate()
                self.accessibilityTimer = nil
                self.statusBarController.updateState(.idle)
                print("[AC Voice] Ready! Hold Option+Space to dictate.")
            }
        }
    }

    private func startDictation() {
        guard !isProcessing else { return }
        do {
            audioRecorder.onFrequencyBands = { [weak self] bands in
                self?.overlayWindow.updateFrequencyBands(bands)
            }
            try audioRecorder.startRecording()
            statusBarController.updateState(.recording)
            overlayWindow.show(mode: .recording)
        } catch {
            print("[AC Voice] Failed to start recording: \(error)")
            statusBarController.updateState(.error("Mic error"))
        }
    }

    private func stopDictation() {
        guard audioRecorder.isRecording else { return }

        let frames = audioRecorder.stopRecording()

        guard !frames.isEmpty else {
            overlayWindow.hide()
            statusBarController.updateState(.idle)
            return
        }

        isProcessing = true
        statusBarController.updateState(.transcribing)
        overlayWindow.show(mode: .transcribing)

        Task {
            do {
                let text = try await transcriptionEngine.transcribe(
                    frames: frames,
                    translate: statusBarController.translateEnabled
                )
                await MainActor.run {
                    overlayWindow.hide()
                    if !text.isEmpty { textInjector.inject(text) }
                    isProcessing = false
                    statusBarController.updateState(.idle)
                }
            } catch {
                print("[AC Voice] Transcription failed: \(error)")
                await MainActor.run {
                    overlayWindow.hide()
                    isProcessing = false
                    statusBarController.updateState(.idle)
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
