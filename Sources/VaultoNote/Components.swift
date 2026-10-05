import AppKit
import Carbon.HIToolbox
import SwiftUI

/// One key drawn as a physical keycap.
struct Keycap: View {
    let label: String
    var large = false

    var body: some View {
        Text(label)
            .font(.system(size: large ? 15 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(VaultoColor.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, large ? 12 : 8)
            .frame(minWidth: large ? 40 : 26, minHeight: large ? 34 : 24)
            .background(
                RoundedRectangle(cornerRadius: large ? 8 : 6)
                    .fill(VaultoColor.surface)
                    .shadow(color: .black.opacity(0.12), radius: 0, y: large ? 2 : 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: large ? 8 : 6).stroke(VaultoColor.border, lineWidth: 1))
    }
}

struct KeycapRow: View {
    let shortcut: Shortcut
    var large = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                Keycap(label: cap, large: large)
            }
        }
    }
}

/// Click, then press either a single modifier (right ⌥, fn, …) or a shortcut with
/// at least one of ⌘ ⌥ ⌃. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @Binding var isRecording: Bool
    /// A small "Other…" chip instead of the full keycap field (onboarding).
    var compact = false
    @State private var monitor: Any?
    @State private var pendingModifier: ModifierKey?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    if isRecording {
                        Circle().fill(VaultoColor.error).frame(width: 7, height: 7)
                        Text(L10n.t("shortcut.press_keys"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(VaultoColor.primary)
                    } else if compact {
                        Text(L10n.t("shortcut.other"))
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        KeycapRow(shortcut: shortcut)
                    }
                }
                .padding(.horizontal, 10)
                .frame(minWidth: compact ? 0 : 150, minHeight: compact ? 26 : 34)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isRecording ? VaultoColor.primaryLight : VaultoColor.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isRecording ? VaultoColor.primary : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t("shortcut.click_to_change"))

            if let hint {
                Text(hint)
                    .font(VaultoFont.caption)
                    .foregroundStyle(VaultoColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        isRecording ? stop() : begin()
    }

    private func begin() {
        hint = nil
        pendingModifier = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        pendingModifier = nil
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .flagsChanged {
            if let key = ModifierKey(keyCode: event.keyCode) {
                if event.modifierFlags.contains(key.flag) {
                    pendingModifier = key
                } else if pendingModifier == key {
                    shortcut = .modifier(key)
                    stop()
                }
            } else if [55, 56, 58, 59].contains(event.keyCode), event.modifierFlags.contains(.deviceIndependentFlagsMask) {
                // Left ⌘ ⇧ ⌥ ⌃ alone would fire on every ordinary shortcut.
                hint = L10n.t("shortcut.use_right_key")
            }
            return
        }

        pendingModifier = nil
        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            stop()
            return
        }
        let isFunctionKey = (122...135).contains(Int(event.keyCode)) || [96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120].contains(Int(event.keyCode))
        guard !modifiers.subtracting(.shift).isEmpty || isFunctionKey else {
            hint = L10n.t("shortcut.add_modifier")
            return
        }
        shortcut = .combo(keyCode: UInt32(event.keyCode), modifiers: modifiers.rawValue)
        stop()
    }
}

/// Five dots, `value` of them filled.
struct DotMeter: View {
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < value ? VaultoColor.primary : VaultoColor.border)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Coloured rounded square with a white symbol, as in System Settings' sidebar.
struct IconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27).fill(color.gradient))
    }
}

/// Large page title with an optional one-line explanation underneath.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(VaultoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row title with a secondary description that wraps instead of truncating.
struct RowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(VaultoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
