import AppKit
import AVFoundation
import SwiftUI

/// State shown in the main window; AppDelegate owns the logic and pushes updates here.
final class AppStatus: ObservableObject {
    @Published var modelStatus = ""
    @Published var isModelReady = false
    @Published var micGranted = false
    @Published var accessibilityGranted = false
    @Published var history: [HistoryEntry] = []
    @Published var language = Settings.language
    @Published var triggerKey = Settings.triggerKey
    @Published var modelID = Settings.modelID
    @Published var trailingSpace = Settings.trailingSpace
    @Published var showInDock = Settings.showInDock

    func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = TextInserter.isTrusted
    }
}

struct WindowActions {
    var requestMicrophone: () -> Void
    var requestAccessibility: () -> Void
    var selectLanguage: (String) -> Void
    var selectTriggerKey: (TriggerKey) -> Void
    var selectModel: (String) -> Void
    var setTrailingSpace: (Bool) -> Void
    var setShowInDock: (Bool) -> Void
    var clearHistory: () -> Void
}

final class MainWindowController {
    private var window: NSWindow?
    private let status: AppStatus
    private let actions: WindowActions

    init(status: AppStatus, actions: WindowActions) {
        self.status = status
        self.actions = actions
    }

    func show() {
        status.refreshPermissions()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Vaulto Note"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainView(status: status, actions: actions))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct MainView: View {
    @ObservedObject var status: AppStatus
    let actions: WindowActions
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !status.micGranted || !status.accessibilityGranted { permissions }
                howTo
                settings
                historySection
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(VaultoColor.background)
        .foregroundStyle(VaultoColor.text)
        .tint(VaultoColor.primary)
        .frame(minWidth: 420, minHeight: 480)
        .onReceive(timer) { _ in status.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            Text("Vaulto Note").font(VaultoFont.h2)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(status.isModelReady ? VaultoColor.success : VaultoColor.warning)
                    .frame(width: 7, height: 7)
                Text(status.modelStatus)
                    .font(VaultoFont.captionBold)
                    .foregroundStyle(status.isModelReady ? VaultoColor.primary : VaultoColor.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(VaultoColor.backgroundSecondary))
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Нужны разрешения").font(VaultoFont.sectionTitle)
            permissionRow(
                icon: "mic.fill",
                title: "Микрофон",
                detail: "Чтобы слышать речь",
                granted: status.micGranted,
                action: actions.requestMicrophone
            )
            Divider().overlay(VaultoColor.border)
            permissionRow(
                icon: "keyboard",
                title: "Универсальный доступ",
                detail: "Чтобы ловить клавишу в других приложениях и вставлять текст",
                granted: status.accessibilityGranted,
                action: actions.requestAccessibility
            )
        }
        .vaultoCard()
    }

    private func permissionRow(icon: String, title: String, detail: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, tint: granted ? VaultoColor.success : VaultoColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(VaultoFont.caption).foregroundStyle(VaultoColor.textSecondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(VaultoColor.success)
            } else {
                Button("Разрешить", action: action).buttonStyle(VaultoPrimaryButton())
            }
        }
    }

    private var howTo: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: "waveform", tint: VaultoColor.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Как пользоваться").font(VaultoFont.sectionTitle)
                (Text("Поставьте курсор в любое поле, удерживайте ")
                    + Text(status.triggerKey.title).bold().foregroundColor(VaultoColor.primary)
                    + Text(" и говорите. Отпустите — текст появится в поле."))
                    .font(VaultoFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Короткое нажатие или клавиша вместе с буквой не запускают запись.")
                    .font(VaultoFont.caption)
                    .foregroundStyle(VaultoColor.textTertiary)
            }
        }
        .vaultoCard()
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Настройки").font(VaultoFont.sectionTitle).padding(.bottom, 8)
            settingRow("Язык", icon: "globe") {
                Picker("", selection: Binding(get: { status.language }, set: { actions.selectLanguage($0) })) {
                    ForEach(DictationLanguage.all, id: \.code) { Text($0.title).tag($0.code) }
                }
            }
            settingRow("Клавиша", icon: "command") {
                Picker("", selection: Binding(get: { status.triggerKey }, set: { actions.selectTriggerKey($0) })) {
                    ForEach(TriggerKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            settingRow("Модель", icon: "cpu") {
                Picker("", selection: Binding(get: { status.modelID }, set: { actions.selectModel($0) })) {
                    ForEach(WhisperModel.all, id: \.id) { model in
                        Text("\(model.title) (\(model.sizeLabel))\(model.isDownloaded ? "" : " — скачать")")
                            .tag(model.id)
                    }
                }
            }
            settingRow("Пробел после текста", icon: "space") {
                Toggle("", isOn: Binding(get: { status.trailingSpace }, set: { actions.setTrailingSpace($0) }))
                    .toggleStyle(.switch)
            }
            settingRow("Иконка в Dock", icon: "dock.rectangle", isLast: true) {
                Toggle("", isOn: Binding(get: { status.showInDock }, set: { actions.setShowInDock($0) }))
                    .toggleStyle(.switch)
            }
        }
        .vaultoCard()
    }

    private func settingRow<Control: View>(_ title: String, icon: String, isLast: Bool = false,
                                           @ViewBuilder control: () -> Control) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(VaultoColor.textSecondary)
                Text(title).font(VaultoFont.body)
                Spacer()
                control()
                    .labelsHidden()
                    .fixedSize()
            }
            .padding(.vertical, 8)
            if !isLast { Divider().overlay(VaultoColor.border) }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("История").font(VaultoFont.sectionTitle)
                if !status.history.isEmpty {
                    Text("\(status.history.count)")
                        .font(VaultoFont.captionBold)
                        .foregroundStyle(VaultoColor.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(VaultoColor.primaryLight))
                }
                Spacer()
                if !status.history.isEmpty {
                    Button("Очистить", action: actions.clearHistory)
                        .buttonStyle(.plain)
                        .font(VaultoFont.captionBold)
                        .foregroundStyle(VaultoColor.error)
                }
            }
            if status.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "mic")
                        .font(.system(size: 28))
                        .foregroundStyle(VaultoColor.textTertiary)
                    Text("Здесь появятся ваши диктовки")
                        .font(VaultoFont.body)
                        .foregroundStyle(VaultoColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .vaultoCard()
            } else {
                ForEach(status.history.prefix(30)) { entry in
                    HistoryRow(entry: entry)
                }
            }
        }
    }
}

private struct IconBadge: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
    }
}

/// Mirrors the mobile NoteCard: white card, 16 pt radius, soft shadow.
private struct HistoryRow: View {
    let entry: HistoryEntry
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .font(VaultoFont.notePreview)
                    .foregroundStyle(VaultoColor.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(entry.language.uppercased())
                    Text("·")
                    Text(String(format: "%.0f с", entry.audioSeconds))
                }
                .font(VaultoFont.caption)
                .foregroundStyle(VaultoColor.textTertiary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? VaultoColor.success : VaultoColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(VaultoColor.backgroundSecondary))
            }
            .buttonStyle(.plain)
            .help("Скопировать")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(VaultoColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(VaultoColor.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}
