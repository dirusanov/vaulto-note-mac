import AppKit
import SwiftUI

/// First-run flow: one screen per step, permissions are requested only when the user
/// asks for them, and each step moves on by itself once its condition is met.
final class OnboardingWindowController {
    private var window: NSWindow?
    private let app: AppController
    private let onFinish: () -> Void

    init(app: AppController, onFinish: @escaping () -> Void) {
        self.app = app
        self.onFinish = onFinish
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: OnboardingView(app: app) { [weak self] in
                self?.finish()
            })
            window.setContentSize(NSSize(width: 600, height: 560))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        Settings.onboardingDone = true
        window?.close()
        window = nil
        onFinish()
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, microphone, accessibility, shortcut, practice
}

struct OnboardingView: View {
    @ObservedObject var app: AppController
    let finish: () -> Void
    @State private var step: OnboardingStep

    init(app: AppController, step: OnboardingStep = .welcome, finish: @escaping () -> Void) {
        self.app = app
        self.finish = finish
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(current: step.rawValue, count: OnboardingStep.allCases.count)
                .padding(.top, 22)
            Spacer(minLength: 12)
            Group {
                switch step {
                case .welcome: WelcomeStep(next: advance)
                case .microphone: MicrophoneStep(app: app, next: advance)
                case .accessibility: AccessibilityStep(app: app, next: advance)
                case .shortcut: ShortcutStep(app: app, next: advance)
                case .practice: PracticeStep(app: app, finish: finish)
                }
            }
            .frame(maxWidth: 460)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 32)
        .frame(width: 600, height: 560)
        .background(VaultoColor.background)
        .foregroundStyle(VaultoColor.text)
        .tint(VaultoColor.primary)
        .environment(\.locale, L10n.locale)
    }

    private func advance() {
        if step == .welcome { app.prepareModel() }
        var next = OnboardingStep(rawValue: step.rawValue + 1) ?? .practice
        // Skip steps whose permission is already in place (e.g. reinstall).
        if next == .microphone && app.micGranted { next = .accessibility }
        if next == .accessibility && app.accessibilityGranted { next = .shortcut }
        withAnimation(.spring(duration: 0.4)) { step = next }
    }
}

private struct ProgressDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? VaultoColor.primary : VaultoColor.border)
                    .frame(width: i == current ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(duration: 0.3), value: current)
    }
}

/// Shared layout of a step: big icon, title, text, custom content, primary button.
private struct StepLayout<Content: View>: View {
    let icon: String
    var iconColor: Color = VaultoColor.primary
    let title: String
    let text: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 72, height: 72)
                .background(Circle().fill(iconColor.opacity(0.12)))
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(VaultoColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

private struct BigButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(enabled ? VaultoColor.primary : VaultoColor.textTertiary))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)
    }
}

private struct SkipButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(VaultoColor.textSecondary)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            VStack(spacing: 8) {
                Text("Vaulto Note").font(.system(size: 30, weight: .bold))
                Text(L10n.t("onboarding.welcome_text"))
                    .font(.system(size: 15))
                    .foregroundStyle(VaultoColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                feature("lock.fill", L10n.t("onboarding.feature_private"))
                feature("keyboard", L10n.t("onboarding.feature_any_app"))
                feature("globe", L10n.t("onboarding.feature_languages"))
            }
            .padding(.vertical, 4)
            BigButton(title: L10n.t("onboarding.start"), action: next)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VaultoColor.primary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(VaultoColor.primaryLight))
            Text(text).font(.system(size: 14))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 440)
    }
}

private struct MicrophoneStep: View {
    @ObservedObject var app: AppController
    let next: () -> Void

    var body: some View {
        StepLayout(icon: "mic.fill", title: L10n.t("onboarding.mic_title"), text: L10n.t("onboarding.mic_text")) {
            VStack(spacing: 12) {
                if app.micGranted {
                    GrantedBadge()
                } else {
                    BigButton(title: L10n.t("onboarding.mic_button"), action: app.requestMicrophone)
                }
            }
            .padding(.top, 6)
        }
        .onChange(of: app.micGranted) { _, granted in
            if granted { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: next) }
        }
    }
}

private struct AccessibilityStep: View {
    @ObservedObject var app: AppController
    let next: () -> Void

    var body: some View {
        StepLayout(icon: "hand.raised.fill", iconColor: Color(red: 0.55, green: 0.36, blue: 0.96),
                   title: L10n.t("onboarding.ax_title"), text: L10n.t("onboarding.ax_text")) {
            VStack(spacing: 14) {
                if app.accessibilityGranted {
                    GrantedBadge()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        instruction(1, L10n.t("onboarding.ax_step1"))
                        instruction(2, L10n.t("onboarding.ax_step2"))
                    }
                    .padding(14)
                    .frame(maxWidth: 360, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(VaultoColor.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(VaultoColor.border, lineWidth: 1))
                    BigButton(title: L10n.t("onboarding.ax_button"), action: app.requestAccessibility)
                    SkipButton(title: L10n.t("onboarding.ax_skip"), action: next)
                }
            }
            .padding(.top, 2)
        }
        .onChange(of: app.accessibilityGranted) { _, granted in
            guard granted else { return }
            // System Settings is in front now; come back so the user sees the next step.
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: next)
        }
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(VaultoColor.primary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(VaultoColor.primaryLight))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ShortcutStep: View {
    @ObservedObject var app: AppController
    let next: () -> Void

    private let presets: [Shortcut] = [.modifier(.rightOption), .modifier(.rightCommand), .modifier(.fn)]

    var body: some View {
        StepLayout(icon: "command", iconColor: Color(red: 0.93, green: 0.28, blue: 0.6),
                   title: L10n.t("onboarding.shortcut_title"), text: L10n.t("onboarding.shortcut_text")) {
            VStack(spacing: 16) {
                KeycapRow(shortcut: app.shortcut, large: true)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(VaultoColor.primaryLight))
                HStack(spacing: 8) {
                    ForEach(presets, id: \.title) { preset in
                        Button { app.shortcut = preset } label: {
                            Text(preset.title)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(app.shortcut == preset ? VaultoColor.primaryLight : VaultoColor.backgroundSecondary))
                                .overlay(Capsule().stroke(app.shortcut == preset ? VaultoColor.primary : .clear, lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)
                    }
                    ShortcutRecorder(shortcut: $app.shortcut, isRecording: $app.isRecordingShortcut, compact: true)
                }
                BigButton(title: L10n.t("onboarding.continue"), action: next)
            }
            .padding(.top, 4)
        }
    }
}

private struct PracticeStep: View {
    @ObservedObject var app: AppController
    let finish: () -> Void
    @State private var text = ""
    @State private var startCount = 0
    @FocusState private var focused: Bool

    private var succeeded: Bool { app.history.count > startCount }

    var body: some View {
        StepLayout(icon: succeeded ? "checkmark" : "waveform",
                   iconColor: succeeded ? VaultoColor.success : VaultoColor.primary,
                   title: succeeded ? L10n.t("onboarding.practice_done") : L10n.t("onboarding.practice_title"),
                   text: succeeded ? L10n.t("onboarding.practice_done_text") :
                       L10n.t("onboarding.practice_text", app.shortcut.inlineTitle)) {
            VStack(spacing: 14) {
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(10)
                    .frame(height: 96)
                    .background(RoundedRectangle(cornerRadius: 12).fill(VaultoColor.surface))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focused ? VaultoColor.primary : VaultoColor.border, lineWidth: focused ? 1.5 : 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(L10n.t("onboarding.practice_placeholder"))
                                .font(.system(size: 15))
                                .foregroundStyle(VaultoColor.textTertiary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                modelStatus
                if succeeded {
                    BigButton(title: L10n.t("onboarding.finish"), action: finish)
                } else {
                    SkipButton(title: L10n.t("onboarding.skip_practice"), action: finish)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            startCount = app.history.count
            focused = true
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        if app.downloadingModelID != nil {
            HStack(spacing: 10) {
                ProgressView(value: app.downloadProgress).frame(width: 160)
                Text(L10n.t("onboarding.model_downloading", Int(app.downloadProgress * 100)))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(VaultoColor.textSecondary)
            }
        } else if app.modelState == .loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("onboarding.model_preparing"))
                    .font(.system(size: 12))
                    .foregroundStyle(VaultoColor.textSecondary)
            }
        } else if case .failed(let message) = app.modelState {
            Text(message).font(.system(size: 12)).foregroundStyle(VaultoColor.error)
        }
    }
}

private struct GrantedBadge: View {
    var body: some View {
        Label(L10n.t("general.granted"), systemImage: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(VaultoColor.success)
            .transition(.scale.combined(with: .opacity))
    }
}
