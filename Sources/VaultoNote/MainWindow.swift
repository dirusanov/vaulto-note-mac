import AppKit
import SwiftUI

extension Page {
    var title: String { L10n.t("page.\(rawValue)") }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .shortcuts: return "command"
        case .transcription: return "waveform"
        case .history: return "clock.fill"
        case .general: return "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .home: return VaultoColor.primary
        case .shortcuts: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .transcription: return Color(red: 0.93, green: 0.28, blue: 0.6)
        case .history: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .general: return Color(red: 0.42, green: 0.46, blue: 0.49)
        }
    }
}

final class MainWindowController {
    private var window: NSWindow?
    private let app: AppController

    init(app: AppController) {
        self.app = app
    }

    func show(page: Page? = nil) {
        if let page { app.page = page }
        app.refreshPermissions()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Vaulto Note"
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: RootView(app: app))
            window.setContentSize(NSSize(width: 920, height: 640))
            window.contentMinSize = NSSize(width: 760, height: 520)
            window.center()
            window.setFrameAutosaveName("VaultoNoteMain")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct RootView: View {
    @ObservedObject var app: AppController

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { app.page }, set: { if let page = $0 { app.page = page } })) {
                ForEach(Page.allCases) { page in
                    Label {
                        Text(page.title)
                    } icon: {
                        IconTile(systemName: page.icon, color: page.color)
                    }
                    .tag(page)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { StatusFooter(app: app) }
        } detail: {
            PageView(app: app, page: app.page)
                .navigationTitle(app.page.title)
        }
        .tint(VaultoColor.primary)
        .environment(\.locale, L10n.locale)
        // Re-render every string when the interface language changes.
        .id(app.interfaceLanguage)
    }
}

struct PageView: View {
    @ObservedObject var app: AppController
    let page: Page

    var body: some View {
        switch page {
        case .home: HomePage(app: app)
        case .shortcuts: ShortcutsPage(app: app)
        case .transcription: TranscriptionPage(app: app)
        case .history: HistoryPage(app: app)
        case .general: GeneralPage(app: app)
        }
    }
}

/// Status pill pinned to the bottom of the sidebar.
private struct StatusFooter: View {
    @ObservedObject var app: AppController

    private var color: Color {
        switch app.phase {
        case .recording: return VaultoColor.error
        case .transcribing: return VaultoColor.primary
        case .idle: return app.isReady ? VaultoColor.success : VaultoColor.warning
        }
    }

    private var text: String {
        switch app.phase {
        case .recording: return L10n.t("hud.listening")
        case .transcribing: return L10n.t("hud.transcribing")
        case .idle: return app.statusText
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VaultoColor.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(VaultoColor.backgroundSecondary.opacity(0.7)))
        .padding(10)
    }
}

// MARK: - Home

struct HomePage: View {
    @ObservedObject var app: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if !app.isReady { SetupChecklist(app: app) }
                stats
                recent
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(VaultoColor.background)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            RecordButton(app: app)
            VStack(spacing: 6) {
                Text(heroTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                if app.phase == .idle {
                    HStack(spacing: 6) {
                        Text(L10n.t("home.or_hold"))
                            .foregroundStyle(VaultoColor.textSecondary)
                        KeycapRow(shortcut: app.shortcut)
                        Text(L10n.t("home.in_any_app"))
                            .foregroundStyle(VaultoColor.textSecondary)
                    }
                    .font(.system(size: 13))
                    Button(L10n.t("home.change_shortcut")) { app.page = .shortcuts }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            if let result = app.inAppResult, app.phase == .idle {
                InAppResult(text: result)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .vaultoCard()
        .animation(.spring(duration: 0.3), value: app.phase)
        .animation(.spring(duration: 0.3), value: app.inAppResult)
    }

    private var heroTitle: String {
        switch app.phase {
        case .idle: return L10n.t("home.click_to_record")
        case .recording: return L10n.t("home.click_to_stop")
        case .transcribing: return L10n.t("hud.transcribing")
        }
    }

    private var stats: some View {
        let words = app.history.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        let minutes = app.history.reduce(0) { $0 + $1.audioSeconds } / 60
        return HStack(spacing: 12) {
            StatTile(value: "\(app.history.count)", label: L10n.t("home.stat_dictations"), icon: "mic.fill")
            StatTile(value: "\(words)", label: L10n.t("home.stat_words"), icon: "text.word.spacing")
            StatTile(value: String(format: "%.0f", minutes.rounded(.up)), label: L10n.t("home.stat_minutes"), icon: "clock")
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("home.recent")).font(VaultoFont.sectionTitle)
                Spacer()
                if !app.history.isEmpty {
                    Button(L10n.t("home.show_all")) { app.page = .history }
                        .buttonStyle(.link)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            if app.history.isEmpty {
                EmptyHistory()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .vaultoCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.history.prefix(4).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(VaultoColor.border) }
                        RecentRow(entry: entry) { app.copy(entry) }
                    }
                }
                .vaultoCard()
            }
        }
    }
}

/// Big round microphone button: click to record, click again to transcribe.
private struct RecordButton: View {
    @ObservedObject var app: AppController

    private var isRecording: Bool {
        if case .recording = app.phase { return true }
        return false
    }

    var body: some View {
        Button(action: app.toggleRecordingFromWindow) {
            ZStack {
                // Halo that breathes with the voice level while recording.
                Circle()
                    .fill((isRecording ? VaultoColor.error : VaultoColor.primary).opacity(0.15))
                    .frame(width: 112, height: 112)
                    .scaleEffect(isRecording ? 1 + CGFloat(app.level) * 0.35 : 1)
                    .animation(.easeOut(duration: 0.1), value: app.level)
                Circle()
                    .fill(isRecording ? VaultoColor.error : VaultoColor.primary)
                    .frame(width: 84, height: 84)
                    .shadow(color: (isRecording ? VaultoColor.error : VaultoColor.primary).opacity(0.35), radius: 12, y: 4)
                switch app.phase {
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                case .recording(let started):
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 22, height: 22)
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.9))
                        }
                    }
                case .transcribing:
                    ProgressView().controlSize(.regular).tint(.white)
                }
            }
            .frame(width: 124, height: 124)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(app.phase == .transcribing)
        .help(L10n.t("home.click_to_record"))
    }
}

/// Result of a dictation recorded with the window's button (already on the clipboard).
private struct InAppResult: View {
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 15))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Label(L10n.t("home.result_copied"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VaultoColor.success)
                Spacer()
                CopyButton(copied: $copied) { TextInserter.copy(text) }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(VaultoColor.background))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(VaultoColor.border, lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(VaultoColor.primary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(VaultoColor.primaryLight))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(VaultoColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(VaultoColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VaultoColor.border, lineWidth: 1))
    }
}

private struct RecentRow: View {
    let entry: HistoryEntry
    let copy: () -> Void
    @State private var copied = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.text)
                .font(.system(size: 14))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.date.formatted(.relative(presentation: .named).locale(L10n.locale)))
                .font(.system(size: 12))
                .foregroundStyle(VaultoColor.textTertiary)
                .lineLimit(1)
                .fixedSize()
            CopyButton(copied: $copied, action: copy)
                .opacity(hovering || copied ? 1 : 0.4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct CopyButton: View {
    @Binding var copied: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(copied ? VaultoColor.success : VaultoColor.textSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(VaultoColor.backgroundSecondary))
        }
        .buttonStyle(.plain)
        .help(L10n.t("window.copy"))
    }
}

private struct EmptyHistory: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 26))
                .foregroundStyle(VaultoColor.textTertiary)
            Text(L10n.t("window.history_empty"))
                .font(.system(size: 13))
                .foregroundStyle(VaultoColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// First-run steps; disappears once everything is in place.
private struct SetupChecklist: View {
    @ObservedObject var app: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("setup.title")).font(VaultoFont.sectionTitle)
            step(1, title: L10n.t("window.mic"), detail: L10n.t("window.mic_detail"), done: app.micGranted) {
                Button(L10n.t("window.allow"), action: app.requestMicrophone).buttonStyle(VaultoPrimaryButton())
            }
            step(2, title: L10n.t("window.accessibility"), detail: L10n.t("window.accessibility_detail"),
                 done: app.accessibilityGranted) {
                Button(L10n.t("window.allow"), action: app.requestAccessibility).buttonStyle(VaultoPrimaryButton())
            }
            step(3, title: L10n.t("setup.model", app.selectedModel.name), detail: L10n.t("setup.model_detail"),
                 done: app.modelState == .ready) {
                if app.downloadingModelID != nil {
                    HStack(spacing: 8) {
                        ProgressView(value: app.downloadProgress)
                            .frame(width: 120)
                        Text("\(Int(app.downloadProgress * 100))%")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(VaultoColor.textSecondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                } else if app.modelState == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L10n.t("model.download")) { app.download(app.selectedModel) }
                        .buttonStyle(VaultoPrimaryButton())
                }
            }
        }
        .vaultoCard()
    }

    private func step<Action: View>(_ number: Int, title: String, detail: String, done: Bool,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? VaultoColor.success : VaultoColor.primaryLight)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(VaultoColor.primary)
                }
            }
            .frame(width: 24, height: 24)
            RowLabel(title: title, detail: detail)
            Spacer(minLength: 12)
            if !done { action() }
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsPage: View {
    @ObservedObject var app: AppController

    private let presets: [Shortcut] = [
        .modifier(.rightOption),
        .modifier(.rightCommand),
        .modifier(.fn),
        .combo(keyCode: 49, modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue),
    ]

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    ShortcutRecorder(shortcut: $app.shortcut, isRecording: $app.isRecordingShortcut)
                } label: {
                    RowLabel(title: L10n.t("shortcut.title"), detail: L10n.t("shortcut.detail"))
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.title) { preset in
                            Button { app.shortcut = preset } label: {
                                KeycapRow(shortcut: preset)
                                    .padding(5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(app.shortcut == preset ? VaultoColor.primaryLight : VaultoColor.backgroundSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .stroke(app.shortcut == preset ? VaultoColor.primary : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } label: {
                    Text(L10n.t("shortcut.presets"))
                }
                if app.shortcut == .modifier(.fn) {
                    Label(L10n.t("shortcut.fn_hint"), systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(VaultoColor.textSecondary)
                }
                if app.shortcut.isModifier && !app.accessibilityGranted {
                    Label(L10n.t("shortcut.needs_accessibility"), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(VaultoColor.warning)
                }
            }

            Section(L10n.t("mode.title")) {
                ForEach(TriggerMode.allCases, id: \.self) { mode in
                    ModeRow(mode: mode, shortcut: app.shortcut, isSelected: app.triggerMode == mode) {
                        app.triggerMode = mode
                    }
                }
            }

            Section {
                Toggle(isOn: $app.cancelWithEscape) {
                    RowLabel(title: L10n.t("shortcut.escape"), detail: L10n.t("shortcut.escape_detail"))
                }
                LabeledContent {
                    KeycapRow(shortcut: .combo(keyCode: 9, modifiers: NSEvent.ModifierFlags([.control, .command]).rawValue))
                } label: {
                    RowLabel(title: L10n.t("shortcut.paste_last"), detail: L10n.t("shortcut.paste_last_detail"))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModeRow: View {
    let mode: TriggerMode
    let shortcut: Shortcut
    let isSelected: Bool
    let select: () -> Void

    private var icon: String {
        switch mode {
        case .hybrid: return "hand.tap.fill"
        case .hold: return "hand.point.down.fill"
        case .toggle: return "playpause.fill"
        }
    }

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? VaultoColor.primary : VaultoColor.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(L10n.t("mode.\(mode.rawValue).title")).font(.system(size: 13, weight: .semibold))
                        if mode == .hybrid { RecommendedBadge() }
                    }
                    Text(L10n.t("mode.\(mode.rawValue).summary", shortcut.inlineTitle))
                        .font(.system(size: 12))
                        .foregroundStyle(VaultoColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? VaultoColor.primary : VaultoColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RecommendedBadge: View {
    var body: some View {
        Text(L10n.t("common.recommended"))
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(VaultoColor.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(VaultoColor.primaryLight))
    }
}

// MARK: - Transcription

struct TranscriptionPage: View {
    @ObservedObject var app: AppController

    var body: some View {
        Form {
            Section {
                ForEach(WhisperModel.all) { model in
                    ModelCard(app: app, model: model)
                }
                if let error = app.downloadError {
                    Label(L10n.t("model.download_error", error), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(VaultoColor.error)
                }
            } header: {
                Text(L10n.t("settings.model"))
            } footer: {
                Label(L10n.t("model.private_note"), systemImage: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VaultoColor.textSecondary)
            }

            Section {
                Picker(selection: $app.speechLanguage) {
                    ForEach(DictationLanguage.all, id: \.code) { Text($0.title).tag($0.code) }
                } label: {
                    RowLabel(title: L10n.t("settings.speech_language"), detail: L10n.t("language.detail"))
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    RowLabel(title: L10n.t("vocabulary.title"), detail: L10n.t("vocabulary.detail"))
                    TextField("", text: $app.vocabulary, prompt: Text(L10n.t("vocabulary.placeholder")), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelCard: View {
    @ObservedObject var app: AppController
    let model: WhisperModel
    @State private var confirmDelete = false

    private var isSelected: Bool { app.selectedModelID == model.id }
    private var isDownloading: Bool { app.downloadingModelID == model.id }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? VaultoColor.primary : VaultoColor.textTertiary)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(model.name).font(.system(size: 14, weight: .semibold))
                    if model.isRecommended { RecommendedBadge() }
                }
                Text(model.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(VaultoColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    meter(L10n.t("model.speed"), model.speed)
                    meter(L10n.t("model.accuracy"), model.accuracy)
                    Text(model.sizeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VaultoColor.textTertiary)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if !isDownloading { app.selectModel(model) } }
        .confirmationDialog(L10n.t("model.delete_confirm", model.name), isPresented: $confirmDelete) {
            Button(L10n.t("model.delete"), role: .destructive) { app.deleteModel(model) }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isDownloading {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: app.downloadProgress).frame(width: 110)
                    Text("\(Int(app.downloadProgress * 100))%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(VaultoColor.textSecondary)
                }
                Button { app.cancelDownload() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(VaultoColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L10n.t("model.cancel"))
            }
        } else if !model.isDownloaded {
            Button(L10n.t("model.download")) { app.download(model) }
                .disabled(app.downloadingModelID != nil)
        } else if isSelected {
            if app.modelState == .loading {
                ProgressView().controlSize(.small)
            } else {
                Label(L10n.t("model.active"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VaultoColor.success)
                    .fixedSize()
            }
        } else {
            Menu {
                Button(L10n.t("model.use")) { app.selectModel(model) }
                Button(L10n.t("model.delete"), role: .destructive) { confirmDelete = true }
            } label: {
                Text(L10n.t("model.downloaded"))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func meter(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(VaultoColor.textTertiary)
                .lineLimit(1)
                .fixedSize()
            DotMeter(value: value)
        }
    }
}

// MARK: - History

struct HistoryPage: View {
    @ObservedObject var app: AppController
    @State private var query = ""
    @State private var selection: UUID?
    @State private var confirmClear = false

    private var filtered: [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return app.history }
        return app.history.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Entries grouped by calendar day, newest first.
    private var groups: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    private var selected: HistoryEntry? {
        filtered.first { $0.id == selection } ?? filtered.first
    }

    var body: some View {
        Group {
            if app.history.isEmpty {
                EmptyHistory().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    list.frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                    detail.frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(VaultoColor.background)
        .searchable(text: $query, placement: .toolbar, prompt: L10n.t("history.search"))
        .toolbar {
            if !app.history.isEmpty {
                Button { confirmClear = true } label: {
                    Label(L10n.t("menu.clear_history"), systemImage: "trash")
                }
                .help(L10n.t("menu.clear_history"))
            }
        }
        .confirmationDialog(L10n.t("history.clear_confirm"), isPresented: $confirmClear) {
            Button(L10n.t("menu.clear_history"), role: .destructive) { app.clearHistory() }
        }
    }

    private var list: some View {
        List(selection: Binding(get: { selected?.id }, set: { selection = $0 })) {
            ForEach(groups, id: \.day) { group in
                Section(Self.dayTitle(group.day)) {
                    ForEach(group.entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.text)
                                .font(.system(size: 13))
                                .lineLimit(2)
                            Text(entry.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))
                                .font(.system(size: 11))
                                .foregroundStyle(VaultoColor.textTertiary)
                        }
                        .padding(.vertical, 3)
                        .tag(entry.id)
                        .contextMenu {
                            Button(L10n.t("window.copy")) { app.copy(entry) }
                            Button(L10n.t("history.delete"), role: .destructive) { app.delete(entry) }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if filtered.isEmpty {
                Text(L10n.t("history.no_results"))
                    .font(.system(size: 13))
                    .foregroundStyle(VaultoColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selected {
            HistoryDetail(entry: entry, copy: { app.copy(entry) }, delete: {
                selection = nil
                app.delete(entry)
            })
            .id(entry.id)
        } else {
            Color.clear
        }
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return L10n.t("history.today") }
        if calendar.isDateInYesterday(day) { return L10n.t("history.yesterday") }
        return day.formatted(.dateTime.day().month(.wide).year().locale(L10n.locale))
    }
}

private struct HistoryDetail: View {
    let entry: HistoryEntry
    let copy: () -> Void
    let delete: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Label(entry.date.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(L10n.locale)), systemImage: "calendar")
                Label(entry.language.uppercased(), systemImage: "globe")
                Label(L10n.t("unit.seconds", Int(entry.audioSeconds.rounded())), systemImage: "waveform")
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(VaultoColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                Text(entry.text)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }

            Divider().overlay(VaultoColor.border)
            HStack {
                Button(action: delete) {
                    Label(L10n.t("history.delete"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(VaultoColor.error)
                Spacer()
                Button {
                    copy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? L10n.t("history.copied") : L10n.t("window.copy"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(VaultoPrimaryButton())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(VaultoColor.surface)
    }
}

// MARK: - General

struct GeneralPage: View {
    @ObservedObject var app: AppController

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("settings.interface_language"), selection: $app.interfaceLanguage) {
                    Text(L10n.t("lang.system", L10n.name(of: L10n.systemLanguage))).tag("system")
                    Divider()
                    ForEach(L10n.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
            }

            Section(L10n.t("page.output")) {
                Toggle(isOn: $app.autoPaste) {
                    RowLabel(title: L10n.t("output.auto_paste"), detail: L10n.t("output.auto_paste_detail"))
                }
                Toggle(isOn: $app.restoreClipboard) {
                    RowLabel(title: L10n.t("output.restore_clipboard"), detail: L10n.t("output.restore_clipboard_detail"))
                }
                .disabled(!app.autoPaste)
                Toggle(isOn: $app.trailingSpace) {
                    RowLabel(title: L10n.t("settings.trailing_space"), detail: L10n.t("output.trailing_space_detail"))
                }
                Toggle(isOn: $app.playSounds) {
                    RowLabel(title: L10n.t("output.sounds"), detail: L10n.t("output.sounds_detail"))
                }
            }

            Section {
                Toggle(isOn: Binding(get: { app.launchAtLogin }, set: { app.launchAtLogin = $0 })) {
                    RowLabel(title: L10n.t("general.launch_at_login"), detail: L10n.t("general.launch_at_login_detail"))
                }
                Toggle(isOn: $app.showInDock) {
                    RowLabel(title: L10n.t("settings.dock_icon"), detail: L10n.t("general.dock_detail"))
                }
            }

            Section(L10n.t("general.permissions")) {
                permissionRow(L10n.t("window.mic"), L10n.t("window.mic_detail"), app.micGranted, app.requestMicrophone)
                permissionRow(L10n.t("window.accessibility"), L10n.t("window.accessibility_detail"),
                              app.accessibilityGranted, app.requestAccessibility)
            }

            Section {
                LabeledContent(L10n.t("general.models_folder")) {
                    Button(L10n.t("general.show_in_finder")) { NSWorkspace.shared.open(AppPaths.models) }
                }
                LabeledContent(L10n.t("general.welcome_again")) {
                    Button(L10n.t("general.show")) { app.onShowOnboarding?() }
                }
                LabeledContent(L10n.t("general.version")) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                        .foregroundStyle(VaultoColor.textSecondary)
                }
                UpdateSettings(updates: app.updates)
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ title: String, _ detail: String, _ granted: Bool,
                               _ action: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted {
                Label(L10n.t("general.granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(VaultoColor.success)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
            } else {
                Button(L10n.t("window.allow"), action: action).buttonStyle(VaultoPrimaryButton())
            }
        } label: {
            RowLabel(title: title, detail: detail)
        }
    }
}


private struct UpdateSettings: View {
    @ObservedObject var updates: UpdateManager

    var body: some View {
        Toggle(isOn: Binding(get: { updates.automaticallyChecksForUpdates },
                             set: { updates.setAutomaticChecks($0) })) {
            RowLabel(title: L10n.t("general.auto_updates"), detail: L10n.t("general.updates_detail"))
        }
        .disabled(!updates.isStarted)
        LabeledContent(L10n.t("general.updates")) {
            Button(L10n.t("general.check_updates")) { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
        }
    }
}
