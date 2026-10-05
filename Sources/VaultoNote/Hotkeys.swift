import AppKit
import Carbon.HIToolbox

/// A single modifier key used on its own, e.g. right ⌥. Detected through
/// `flagsChanged`, which needs Accessibility to be seen in other apps.
enum ModifierKey: String, CaseIterable, Codable {
    case rightOption, rightCommand, rightShift, rightControl, fn

    var keyCode: UInt16 {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightShift: return 60
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: return .option
        case .rightCommand: return .command
        case .rightShift: return .shift
        case .rightControl: return .control
        case .fn: return .function
        }
    }

    var symbol: String {
        switch self {
        case .rightOption: return "⌥"
        case .rightCommand: return "⌘"
        case .rightShift: return "⇧"
        case .rightControl: return "⌃"
        case .fn: return "fn"
        }
    }

    /// Localized "Right ⌥" style name, for keycaps.
    var title: String {
        switch self {
        case .fn: return L10n.t("key.fn")
        default: return L10n.t("key.right", symbol)
        }
    }

    /// Same name as it reads inside a sentence ("hold right ⌥ and speak").
    var inlineTitle: String {
        switch self {
        case .fn: return L10n.t("key.fn")
        default: return L10n.t("key.right_inline", symbol)
        }
    }

    init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }
}

/// What starts dictation: one modifier key or a regular shortcut such as ⌃⌥Space.
enum Shortcut: Equatable, Codable {
    case modifier(ModifierKey)
    case combo(keyCode: UInt32, modifiers: UInt) // NSEvent.ModifierFlags raw value

    static let `default` = Shortcut.modifier(.rightOption)

    var isModifier: Bool {
        if case .modifier = self { return true }
        return false
    }

    /// Keycaps to draw, in display order.
    var keycaps: [String] {
        switch self {
        case .modifier(let key):
            return [key.title]
        case .combo(let keyCode, let raw):
            let flags = NSEvent.ModifierFlags(rawValue: raw)
            var caps: [String] = []
            if flags.contains(.control) { caps.append("⌃") }
            if flags.contains(.option) { caps.append("⌥") }
            if flags.contains(.shift) { caps.append("⇧") }
            if flags.contains(.command) { caps.append("⌘") }
            caps.append(KeyNames.name(for: UInt16(keyCode)))
            return caps
        }
    }

    var title: String { keycaps.joined(separator: " ") }

    /// Name to embed in running text.
    var inlineTitle: String {
        if case .modifier(let key) = self { return key.inlineTitle }
        return keycaps.joined()
    }
}

enum TriggerMode: String, CaseIterable, Codable {
    /// Hold to talk; a short tap starts hands-free recording, the next press stops it.
    case hybrid
    /// Talk while the key is held.
    case hold
    /// Press to start, press again to stop.
    case toggle
}

enum KeyNames {
    private static let special: [UInt16: String] = [
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19",
    ]

    static func name(for keyCode: UInt16) -> String {
        if keyCode == UInt16(kVK_Space) { return L10n.t("key.space") }
        if let name = special[keyCode] { return name }
        return translate(keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// Character the key produces on the ASCII-capable layout, so shortcuts read
    /// "⌥ D" even while a Cyrillic layout is active.
    private static func translate(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}

/// Turns raw key events into start / stop / cancel according to the trigger mode.
final class HotkeyMonitor {
    var shortcut: Shortcut = .default { didSet { if isRunning { start() } } }
    var mode: TriggerMode = .hybrid
    var cancelWithEscape = true

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    /// Presses shorter than this are taps: hands-free in hybrid mode, ignored in hold mode.
    static let tapThreshold: TimeInterval = 0.3

    private enum State {
        case idle
        case held(since: Date)
        case locked
    }

    private var state = State.idle
    private var monitors: [Any] = []
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isRunning = false
    /// Set while the shortcut recorder is open so presses don't start dictation.
    var isSuspended = false
    /// Clock for tap detection; replaced in tests.
    var now: () -> Date = Date.init

    func start() {
        stop()
        isRunning = true
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in
            self?.handle($0)
            return $0
        }) {
            monitors.append(local)
        }
        if case .combo(let keyCode, let modifiers) = shortcut {
            registerCarbonHotKey(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        isRunning = false
        state = .idle
    }

    /// Recording ended or failed elsewhere (menu, error): forget the key state.
    func reset() {
        state = .idle
    }

    /// Recording was started from the menu; the next key press stops it.
    func lock() {
        state = .locked
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        guard !isSuspended else { return }
        if event.type == .keyDown {
            otherKeyDown(event.keyCode)
            return
        }
        guard case .modifier(let key) = shortcut, event.keyCode == key.keyCode else { return }
        if event.modifierFlags.contains(key.flag) { triggerDown() } else { triggerUp() }
    }

    func otherKeyDown(_ keyCode: UInt16) {
        if keyCode == UInt16(kVK_Escape), cancelWithEscape, !isIdle {
            state = .idle
            onCancel?()
            return
        }
        // ⌥ + letter while holding the trigger was a character, not dictation.
        if case .held = state, shortcut.isModifier {
            state = .idle
            onCancel?()
        }
    }

    private var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    func triggerDown() {
        switch state {
        case .idle:
            state = mode == .toggle ? .locked : .held(since: now())
            onStart?()
        case .locked:
            state = .idle
            onStop?()
        case .held:
            break
        }
    }

    func triggerUp() {
        guard case .held(let since) = state else { return }
        let isTap = now().timeIntervalSince(since) < Self.tapThreshold
        switch mode {
        case .hybrid where isTap:
            state = .locked
        case .hold where isTap:
            state = .idle
            onCancel?()
        default:
            state = .idle
            onStop?()
        }
    }

    // MARK: - Carbon hot key (combos work without Accessibility and swallow the keys)

    private func registerCarbonHotKey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.id == 1 else { return OSStatus(eventNotHandledErr) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            guard !monitor.isSuspended else { return noErr }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) {
                monitor.triggerDown()
            } else {
                monitor.triggerUp()
            }
            return noErr
        }, types.count, &types, selfPtr, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x564E_5445), id: 1) // 'VNTE'
        RegisterEventHotKey(keyCode, carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

/// A plain press-only global hot key (used for "paste last dictation").
final class CarbonHotKey {
    var onPress: (() -> Void)?
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(id: UInt32) {
        self.id = id
    }

    deinit { unregister() }

    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        unregister()
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Handlers are chained; let other hot keys' events pass through.
            guard hotKeyID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.onPress?()
            return noErr
        }, 1, &type, selfPtr, &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x564E_5445), id: id)
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
