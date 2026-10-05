import AppKit
import SwiftUI

enum HUDState: Equatable {
    case hidden
    case recording(started: Date)
    case transcribing
    case message(String)
}

final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
    /// Recent levels, oldest first, for the scrolling waveform.
    @Published var levels: [Float] = Array(repeating: 0, count: 24)
}

/// Floating capsule near the bottom of the screen. It never takes focus, so the
/// text still lands in the app the user was typing in.
final class HUDController {
    private let model = HUDModel()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The system shadow follows the capsule's shape.
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }()
    private var hideWork: DispatchWorkItem?

    func show(_ state: HUDState) {
        hideWork?.cancel()
        if case .recording = state {
            model.levels = Array(repeating: 0, count: model.levels.count)
        }
        model.state = state
        guard state != .hidden else {
            panel.orderOut(nil)
            return
        }
        position()
        panel.orderFrontRegardless()
        if case .message = state {
            let work = DispatchWorkItem { [weak self] in self?.show(.hidden) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
        }
    }

    func setLevel(_ level: Float) {
        model.levels.removeFirst()
        model.levels.append(level)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 40))
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VaultoColor.text)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .fixedSize()
            .background(
                RoundedRectangle(cornerRadius: 22, style: .circular)
                    .fill(VaultoColor.surfaceElevated)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .circular).strokeBorder(VaultoColor.border, lineWidth: 1))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .recording(let started):
            HStack(spacing: 10) {
                Circle()
                    .fill(VaultoColor.error)
                    .frame(width: 8, height: 8)
                Waveform(levels: model.levels)
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text(Self.elapsed(from: started, to: context.date))
                        .monospacedDigit()
                }
                Text(L10n.t("hud.esc_cancel"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VaultoColor.textTertiary)
            }
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small).tint(VaultoColor.primary)
                Text(L10n.t("hud.transcribing"))
            }
        case .message(let text):
            Text(text).lineLimit(2).multilineTextAlignment(.center)
        case .hidden:
            EmptyView()
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(VaultoColor.primary)
                    .frame(width: 2.5, height: CGFloat(3 + 18 * min(1, levels[i])))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}
