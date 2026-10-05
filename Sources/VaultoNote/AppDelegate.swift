import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Phase {
        case idle
        case recording(started: Date)
        case transcribing
    }

    /// Presses shorter than this are treated as accidental taps.
    private static let minRecordingSeconds = 0.35

    private let engine = WhisperEngine()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let hud = HUDController()
    private let history = HistoryStore()
    private let models = ModelManager()

    private var statusItem: NSStatusItem!
    private var phase: Phase = .idle
    private var modelStatus = "Модель не загружена"
    private var isModelReady = false
    private var trustTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        recorder.onLevel = { [weak self] level in self?.hud.setLevel(level) }

        hotkey.key = Settings.triggerKey
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.finishRecording() }
        hotkey.onInterrupted = { [weak self] in self?.cancelRecording() }
        hotkey.start()

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        ensureAccessibility()
        loadSelectedModel()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = recorder.stop()
        engine.unload()
    }

    /// Without Accessibility the global key monitor sees nothing and ⌘V cannot be sent.
    /// Monitors installed before trust was granted stay deaf, so reinstall them once it is.
    private func ensureAccessibility() {
        guard !TextInserter.requestTrust() else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard TextInserter.isTrusted else { return }
            timer.invalidate()
            self?.trustTimer = nil
            self?.hotkey.start()
            self?.hud.show(.message("Готово: удерживайте \(Settings.triggerKey.title) и говорите"))
        }
    }

    private func loadSelectedModel() {
        let model = WhisperModel.find(Settings.modelID)
        isModelReady = false
        guard model.isDownloaded else {
            modelStatus = "Модель не скачана"
            downloadModel(model)
            return
        }
        modelStatus = "Загружаю модель…"
        engine.load(modelPath: model.fileURL.path) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.isModelReady = true
                self.modelStatus = "\(model.title) — готово"
            case .failure(let error):
                self.modelStatus = error.localizedDescription
                self.hud.show(.message(error.localizedDescription))
            }
        }
    }

    private func downloadModel(_ model: WhisperModel) {
        guard models.downloading == nil else { return }
        modelStatus = "Скачиваю \(model.title)… 0%"
        models.onProgress = { [weak self] progress in
            self?.modelStatus = "Скачиваю \(model.title)… \(Int(progress * 100))%"
        }
        models.download(model) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if Settings.modelID == model.id { self.loadSelectedModel() }
            case .failure(let error):
                self.modelStatus = "Ошибка загрузки: \(error.localizedDescription)"
                self.hud.show(.message("Не удалось скачать модель"))
            }
        }
    }

    // MARK: - Dictation

    private func startRecording() {
        guard case .idle = phase else { return }
        guard isModelReady else {
            hud.show(.message(modelStatus))
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            hud.show(.message("Нет доступа к микрофону"))
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            return
        }
        do {
            try recorder.start()
            phase = .recording(started: Date())
            hud.show(.recording)
            updateIcon()
        } catch {
            hud.show(.message(error.localizedDescription))
        }
    }

    private func finishRecording() {
        guard case .recording(let started) = phase else { return }
        let samples = recorder.stop()
        guard Date().timeIntervalSince(started) >= Self.minRecordingSeconds else {
            resetToIdle()
            return
        }
        phase = .transcribing
        hud.show(.transcribing)
        updateIcon()

        engine.transcribe(samples: samples, language: Settings.language) { [weak self] result in
            guard let self else { return }
            self.resetToIdle()
            switch result {
            case .success(let transcript):
                guard !transcript.text.isEmpty else {
                    self.hud.show(.message("Речь не распознана"))
                    return
                }
                self.history.add(HistoryEntry(
                    date: Date(),
                    text: transcript.text,
                    language: transcript.language,
                    audioSeconds: transcript.audioSeconds
                ))
                TextInserter.insert(transcript.text + (Settings.trailingSpace ? " " : ""))
            case .failure(let error):
                self.hud.show(.message(error.localizedDescription))
            }
        }
    }

    private func cancelRecording() {
        guard case .recording = phase else { return }
        _ = recorder.stop()
        resetToIdle()
    }

    private func resetToIdle() {
        phase = .idle
        hud.show(.hidden)
        updateIcon()
    }

    @objc private func toggleRecording() {
        switch phase {
        case .idle:
            // Give the menu time to close so the paste lands in the previous app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.startRecording() }
        case .recording: finishRecording()
        case .transcribing: break
        }
    }

    private func updateIcon() {
        let symbol: String
        switch phase {
        case .idle: symbol = "waveform"
        case .recording: symbol = "mic.fill"
        case .transcribing: symbol = "ellipsis.circle"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vaulto Note")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(modelStatus))
        if !TextInserter.isTrusted {
            menu.addItem(item("⚠️ Разрешить Универсальный доступ…", #selector(openAccessibility)))
        }
        menu.addItem(disabledItem("Удерживайте \(Settings.triggerKey.title) и говорите"))

        let recordTitle: String
        if case .recording = phase { recordTitle = "Остановить и вставить" } else { recordTitle = "Начать запись" }
        menu.addItem(item(recordTitle, #selector(toggleRecording)))
        menu.addItem(.separator())

        let historyMenu = NSMenu()
        if history.entries.isEmpty {
            historyMenu.addItem(disabledItem("Пока пусто"))
        } else {
            for (index, entry) in history.entries.prefix(15).enumerated() {
                let title = entry.text.count > 60 ? String(entry.text.prefix(60)) + "…" : entry.text
                let historyItem = item(title, #selector(copyHistoryEntry(_:)))
                historyItem.tag = index
                historyItem.toolTip = entry.text
                historyMenu.addItem(historyItem)
            }
            historyMenu.addItem(.separator())
            historyMenu.addItem(disabledItem("Нажмите на запись, чтобы скопировать"))
            historyMenu.addItem(item("Очистить историю", #selector(clearHistory)))
        }
        menu.addItem(submenu("История", historyMenu))

        let languageMenu = NSMenu()
        for (index, language) in DictationLanguage.all.enumerated() {
            let languageItem = item(language.title, #selector(selectLanguage(_:)))
            languageItem.tag = index
            languageItem.state = language.code == Settings.language ? .on : .off
            languageMenu.addItem(languageItem)
        }
        menu.addItem(submenu("Язык", languageMenu))

        let keyMenu = NSMenu()
        for (index, key) in TriggerKey.allCases.enumerated() {
            let keyItem = item(key.title, #selector(selectTriggerKey(_:)))
            keyItem.tag = index
            keyItem.state = key == Settings.triggerKey ? .on : .off
            keyMenu.addItem(keyItem)
        }
        menu.addItem(submenu("Клавиша", keyMenu))

        let modelMenu = NSMenu()
        for (index, model) in WhisperModel.all.enumerated() {
            let suffix = model.isDownloaded ? "" : " — скачать"
            let modelItem = item("\(model.title) (\(model.sizeLabel))\(suffix)", #selector(selectModel(_:)))
            modelItem.tag = index
            modelItem.state = model.id == Settings.modelID ? .on : .off
            modelMenu.addItem(modelItem)
        }
        modelMenu.addItem(.separator())
        modelMenu.addItem(item("Открыть папку с моделями", #selector(openModelsFolder)))
        menu.addItem(submenu("Модель", modelMenu))

        let spaceItem = item("Пробел после текста", #selector(toggleTrailingSpace))
        spaceItem.state = Settings.trailingSpace ? .on : .off
        menu.addItem(spaceItem)

        menu.addItem(.separator())
        menu.addItem(item("Выйти", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func openAccessibility() {
        TextInserter.requestTrust()
        TextInserter.openAccessibilitySettings()
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard history.entries.indices.contains(sender.tag) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(history.entries[sender.tag].text, forType: .string)
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        Settings.language = DictationLanguage.all[sender.tag].code
    }

    @objc private func selectTriggerKey(_ sender: NSMenuItem) {
        Settings.triggerKey = TriggerKey.allCases[sender.tag]
        hotkey.key = Settings.triggerKey
        hotkey.start()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        let model = WhisperModel.all[sender.tag]
        guard models.downloading == nil else {
            hud.show(.message("Дождитесь окончания загрузки"))
            return
        }
        Settings.modelID = model.id
        loadSelectedModel()
    }

    @objc private func openModelsFolder() {
        NSWorkspace.shared.open(AppPaths.models)
    }

    @objc private func toggleTrailingSpace() {
        Settings.trailingSpace.toggle()
    }
}
