import Cocoa

enum OverlayMode {
    case recording
    case transcribing
}

class OverlayWindow {
    private var window: NSWindow?
    private var contentView: OverlayPillView?
    private var positionTimer: Timer?

    private let pillWidth:  CGFloat = 160
    private let pillHeight: CGFloat = 44
    private let cursorOffset: CGFloat = 20

    func show(mode: OverlayMode) {
        if window != nil { contentView?.setMode(mode); return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.hasShadow = true

        let pill = OverlayPillView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        pill.setMode(mode)
        win.contentView = pill

        updatePosition(for: win)
        win.orderFrontRegardless()
        window = win
        contentView = pill

        // Position update at display refresh rate
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self, let w = self.window else { return }
            self.updatePosition(for: w)
        }
    }

    func hide() {
        positionTimer?.invalidate(); positionTimer = nil
        contentView?.stopAll()
        window?.orderOut(nil)
        window = nil; contentView = nil
    }

    /// Feed raw frequency-band magnitudes (0-1) from the FFT
    func updateFrequencyBands(_ bands: [Float]) {
        contentView?.pushBands(bands)
    }

    private func updatePosition(for win: NSWindow) {
        let m = NSEvent.mouseLocation
        win.setFrameOrigin(NSPoint(x: m.x - pillWidth / 2,
                                   y: m.y - pillHeight - cursorOffset))
    }
}

// MARK: - Pill view

private class OverlayPillView: NSView {

    private var mode: OverlayMode = .recording
    private var displayLink: CVDisplayLink?

    // ── Waveform ─────────────────────────────────────────────────────────────
    private let barCount  = AudioRecorder.bandCount   // 16
    private let barWidth: CGFloat = 2.5
    private let barGap:   CGFloat = 3.0

    private var rawBands:    [Float]  // latest from FFT
    private var smoothBands: [CGFloat] // exponentially smoothed for display

    // ── Spinner ───────────────────────────────────────────────────────────────
    private var spinAngle: CGFloat = 0

    // ── Init ──────────────────────────────────────────────────────────────────
    override init(frame: NSRect) {
        rawBands    = Array(repeating: 0, count: 16)
        smoothBands = Array(repeating: 0, count: 16)
        super.init(frame: frame)
        startDisplayLink()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { stopDisplayLink() }

    // ── Public ────────────────────────────────────────────────────────────────
    func setMode(_ m: OverlayMode) {
        mode = m
        if m == .recording { rawBands = Array(repeating: 0, count: barCount) }
        DispatchQueue.main.async { self.needsDisplay = true }
    }

    func pushBands(_ bands: [Float]) {
        rawBands = bands
    }

    func stopAll() { stopDisplayLink() }

    // ── Display link ──────────────────────────────────────────────────────────
    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, ctx -> CVReturn in
            Unmanaged<OverlayPillView>.fromOpaque(ctx!).takeUnretainedValue().tick()
            return kCVReturnSuccess
        }, ptr)
        CVDisplayLinkStart(dl)
    }

    private func stopDisplayLink() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
        displayLink = nil
    }

    private func tick() {
        switch mode {
        case .recording:
            // Smooth each band: fast attack, slow decay
            for i in 0..<barCount {
                let target = CGFloat(rawBands[i])
                let rate: CGFloat = target > smoothBands[i] ? 0.40 : 0.08
                smoothBands[i] += (target - smoothBands[i]) * rate
            }
        case .transcribing:
            spinAngle = (spinAngle + 3.5).truncatingRemainder(dividingBy: 360)
        }
        DispatchQueue.main.async { self.needsDisplay = true }
    }

    // ── Drawing ───────────────────────────────────────────────────────────────
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()
        switch mode {
        case .recording:    drawSpectrum()
        case .transcribing: drawArcSpinner()
        }
    }

    private func drawBackground() {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: bounds.height / 2,
                                yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
        path.fill()
        NSColor(calibratedWhite: 0.35, alpha: 0.40).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    // Real spectrum bars — each bar is an independent frequency band
    private func drawSpectrum() {
        let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (bounds.width - totalW) / 2
        let centerY = bounds.height / 2
        let maxH = bounds.height * 0.78
        let minH: CGFloat = 2

        for i in 0..<barCount {
            let mag = smoothBands[i]
            let h = minH + (maxH - minH) * mag
            let x = startX + CGFloat(i) * (barWidth + barGap)

            // Colour shifts from neon orange (low) toward bright orange-white (high magnitude)
            let brightness = 0.85 + mag * 0.15
            let alpha      = 0.50 + mag * 0.50
            NSColor(hue: 0.08, saturation: 1.0 - mag * 0.3,
                    brightness: brightness, alpha: alpha).setFill()

            let rect = NSRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
            NSBezierPath(roundedRect: rect,
                         xRadius: barWidth / 2,
                         yRadius: barWidth / 2).fill()
        }
    }

    // Simple rotating arc — clean, minimal, recognisable
    private func drawArcSpinner() {
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        let r:  CGFloat = 11
        let lw: CGFloat = 2.0

        // Faint track
        let track = NSBezierPath()
        track.appendArc(withCenter: NSPoint(x: cx, y: cy),
                        radius: r, startAngle: 0, endAngle: 360)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        track.lineWidth = lw
        track.stroke()

        // Bright arc (~270°)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy),
                      radius: r,
                      startAngle: spinAngle,
                      endAngle:   spinAngle + 270,
                      clockwise:  false)
        NSColor.white.withAlphaComponent(0.90).setStroke()
        arc.lineWidth    = lw
        arc.lineCapStyle = .round
        arc.stroke()
    }
}
