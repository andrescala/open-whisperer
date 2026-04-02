import Cocoa

enum OverlayMode {
    case recording
    case transcribing
}

class OverlayWindow {
    private var window: NSWindow?
    private var contentView: OverlayPillView?
    private var positionTimer: Timer?

    private let pillWidth: CGFloat = 120
    private let pillHeight: CGFloat = 40
    private let cursorOffset: CGFloat = 20

    func show(mode: OverlayMode) {
        if window != nil {
            // Already showing — just switch mode
            contentView?.setMode(mode)
            return
        }

        let frame = NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
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

        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let win = self.window else { return }
            self.updatePosition(for: win)
        }
    }

    func hide() {
        positionTimer?.invalidate()
        positionTimer = nil
        contentView?.stopAll()
        window?.orderOut(nil)
        window = nil
        contentView = nil
    }

    func updateAudioLevel(_ level: Float) {
        contentView?.updateAudioLevel(level)
    }

    private func updatePosition(for win: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let x = mouseLocation.x - pillWidth / 2
        let y = mouseLocation.y - pillHeight - cursorOffset
        win.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Combined pill view with recording + transcribing modes

private class OverlayPillView: NSView {
    private var mode: OverlayMode = .recording
    private var animationTimer: Timer?

    // Recording: audio-reactive bars
    private let barCount = 5
    private var barHeights: [CGFloat]  // Current display heights (0-1)
    private var targetBarHeights: [CGFloat]  // Target heights from audio
    private var audioLevel: CGFloat = 0

    // Transcribing: spinning dots
    private var spinAngle: CGFloat = 0

    override init(frame: NSRect) {
        barHeights = Array(repeating: 0.1, count: barCount)
        targetBarHeights = Array(repeating: 0.1, count: barCount)
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    func setMode(_ newMode: OverlayMode) {
        mode = newMode
        startAnimation()
        needsDisplay = true
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = CGFloat(level)

        // Distribute level across bars with variation for visual interest
        for i in 0..<barCount {
            let variation = CGFloat.random(in: 0.6...1.0)
            targetBarHeights[i] = max(0.08, audioLevel * variation)
        }
    }

    func stopAll() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            switch self.mode {
            case .recording:
                // Smoothly interpolate toward target heights
                for i in 0..<self.barCount {
                    let diff = self.targetBarHeights[i] - self.barHeights[i]
                    self.barHeights[i] += diff * 0.3
                }
            case .transcribing:
                self.spinAngle += 5
                if self.spinAngle >= 360 { self.spinAngle -= 360 }
            }

            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw pill background
        let pillRect = bounds.insetBy(dx: 1, dy: 1)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)

        NSColor(calibratedWhite: 0.1, alpha: 0.9).setFill()
        pillPath.fill()

        NSColor(calibratedWhite: 0.3, alpha: 0.5).setStroke()
        pillPath.lineWidth = 0.5
        pillPath.stroke()

        switch mode {
        case .recording:
            drawWaveformBars()
        case .transcribing:
            drawSpinningDots()
        }
    }

    private func drawWaveformBars() {
        let barWidth: CGFloat = 4
        let barSpacing: CGFloat = 6
        let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalBarsWidth) / 2
        let maxBarHeight = bounds.height * 0.6
        let minBarHeight: CGFloat = 4
        let centerY = bounds.height / 2

        for i in 0..<barCount {
            let barHeight = minBarHeight + (maxBarHeight - minBarHeight) * barHeights[i]

            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = centerY - barHeight / 2

            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            NSColor.systemCyan.setFill()
            barPath.fill()
        }
    }

    private func drawSpinningDots() {
        let dotCount = 3
        let dotRadius: CGFloat = 3.5
        let orbitRadius: CGFloat = 10
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2

        for i in 0..<dotCount {
            let angleOffset = CGFloat(i) * (360.0 / CGFloat(dotCount))
            let angle = (spinAngle + angleOffset) * .pi / 180.0

            let x = centerX + cos(angle) * orbitRadius - dotRadius
            let y = centerY + sin(angle) * orbitRadius - dotRadius

            let dotRect = NSRect(x: x, y: y, width: dotRadius * 2, height: dotRadius * 2)

            // Fade dots based on position for depth effect
            let alpha = 0.4 + 0.6 * ((sin(angle) + 1) / 2)
            NSColor.systemOrange.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}
