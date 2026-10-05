import AppKit

enum TriggerKey: String, CaseIterable {
    case rightOption
    case rightCommand
    case fn

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .fn: return 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        case .fn: return .function
        }
    }

    var title: String {
        switch self {
        case .rightOption: return L10n.t("key.right_option")
        case .rightCommand: return L10n.t("key.right_command")
        case .fn: return L10n.t("key.fn")
        }
    }
}

/// Hold-to-talk on a single modifier key. Modifier presses arrive as `flagsChanged`,
/// so no hotkey registration is needed, but the global monitor only fires once the
/// app is trusted for Accessibility.
final class HotkeyMonitor {
    var key: TriggerKey = .rightOption
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Another key was typed while the trigger was held (e.g. ⌥+letter for a special
    /// character), so the press was not meant as dictation.
    var onInterrupted: (() -> Void)?

    private var monitors: [Any] = []
    private var isDown = false

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isDown = false
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if isDown {
                isDown = false
                onInterrupted?()
            }
            return
        }
        guard event.keyCode == key.keyCode else { return }
        let down = event.modifierFlags.contains(key.flag)
        if down, !isDown {
            isDown = true
            onPress?()
        } else if !down, isDown {
            isDown = false
            onRelease?()
        }
    }
}
