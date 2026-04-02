import Cocoa

class HotkeyManager {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyPressed = false

    // Default: Option + Space
    private let hotkeyKeyCode: CGKeyCode = 49  // Space
    private let hotkeyModifiers: CGEventFlags = .maskAlternate  // Option

    static func checkAccessibility(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() -> Bool {
        guard Self.checkAccessibility(prompt: false) else {
            print("[Whisperer] Accessibility permission not granted")
            return false
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[Whisperer] Failed to create event tap")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Whisperer] Hotkey listener started (Option+Space)")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it was disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Key down: Option + Space (consume initial press AND repeats)
        if type == .keyDown && keyCode == hotkeyKeyCode &&
           event.flags.contains(hotkeyModifiers) {
            if !isHotkeyPressed {
                isHotkeyPressed = true
                onHotkeyDown?()
            }
            return nil  // Consume all repeats while held
        }

        // Key up: Space released (while we were recording)
        if type == .keyUp && keyCode == hotkeyKeyCode && isHotkeyPressed {
            isHotkeyPressed = false
            onHotkeyUp?()
            return nil  // Consume the event
        }

        return Unmanaged.passRetained(event)
    }
}

// C-compatible callback that bridges to the instance method
private let hotkeyCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(proxy: proxy, type: type, event: event)
}
