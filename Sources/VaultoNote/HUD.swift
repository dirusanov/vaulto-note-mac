import AppKit
import SwiftUI

enum HUDState: Equatable {
    case hidden
    case recording
    case transcribing
    case message(String)
}

final class HUDModel: ObservableObject {
    @Published var state: HUDState = .hidden
    @Published var level: Float = 0
}

/// Small floating capsule near the bottom of the screen. It never takes focus, so the
/// text still lands in the app the user was typing in.
final class HUDController {
    private let model = HUDModel()
    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
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
        model.level = level
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 60))
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.state {
            case .recording:
                Circle().fill(Color.red).frame(width: 10, height: 10)
                LevelBars(level: model.level)
                Text("Слушаю…")
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Распознаю…")
            case .message(let text):
                Text(text).lineLimit(2)
            case .hidden:
                EmptyView()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color.black.opacity(0.78)))
    }
}

private struct LevelBars: View {
    let level: Float
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.7, 0.45]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: CGFloat(4 + 16 * min(1, level * weights[i])))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
