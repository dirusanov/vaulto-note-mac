import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Phase {
        case idle
        case recording(started: Date)
        case transcribing
    }

    /// Kept as data rather than a string so the text follows interface language changes.
    private enum ModelState {
        case notLoaded
        case notDownloaded
        case loading
        case ready(WhisperModel)
        case downloading(WhisperModel, Int)
        case loadFailed(String)
        case downloadFailed(String)

        var text: String {
            switch self {
            case .notLoaded: return L10n.t("model.not_loaded")
            case .notDownloaded: return L10n.t("model.not_downloaded")
            case .loading: return L10n.t("model.loading")
            case .ready(let model): return L10n.t("model.ready", model.title)
            case .downloading(let model, let percent): return L10n.t("model.downloading", model.title, percent)
            case .loadFailed(let message): return message
            case .downloadFailed(let message): return L10n.t("model.download_error", message)
            }
        }
    }

    /// Presses shorter than this are treated as accidental taps.
    private static let minRecordingSeconds = 0.35

    private let engine = WhisperEngine()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let hud = HUDController()
    private let history = HistoryStore()
    private let models = ModelManager()

    private let status = AppStatus()
    private lazy var mainWindow = MainWindowController(status: status, actions: WindowActions(
        requestMicrophone: { [weak self] in self?.requestMicrophone() },
        requestAccessibility: { [weak self] in self?.openAccessibility() },
        selectInterfaceLanguage: { [weak self] in self?.setInterfaceLanguage($0) },
        selectLanguage: { [weak self] in self?.setLanguage($0) },
        selectTriggerKey: { [weak self] in self?.setTriggerKey($0) },
        selectModel: { [weak self] in self?.setModel(WhisperModel.find($0)) },
        setTrailingSpace: { [weak self] in
            Settings.trailingSpace = $0
            self?.status.trailingSpace = $0
        },
        setShowInDock: { [weak self] in self?.setShowInDock($0) },
        clearHistory: { [weak self] in self?.clearHistory() }
    ))

    private var statusItem: NSStatusItem!
    private var phase: Phase = .idle
    private var modelState = ModelState.notLoaded {
        didSet { status.modelStatus = modelState.text }
    }
    private var isModelReady = false {
        didSet { status.isModelReady = isModelReady }
    }
    private var trustTimer: Timer?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
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

        status.modelStatus = modelState.text
        status.history = history.entries
        mainWindow.show()

        requestMicrophone()
        ensureAccessibility()
        loadSelectedModel()
    }

    /// Clicking the app in Finder, Spotlight or the Dock while it runs brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.status.refreshPermissions() }
            }
        case .authorized:
            break
        default:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
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
            self?.status.refreshPermissions()
            self?.hud.show(.message(L10n.t("hud.ready_hold", Settings.triggerKey.title)))
        }
    }

    private func loadSelectedModel() {
        let model = WhisperModel.find(Settings.modelID)
        isModelReady = false
        guard model.isDownloaded else {
            modelState = .notDownloaded
            downloadModel(model)
            return
        }
        modelState = .loading
        engine.load(modelPath: model.fileURL.path) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.isModelReady = true
                self.modelState = .ready(model)
            case .failure(let error):
                self.modelState = .loadFailed(error.localizedDescription)
                self.hud.show(.message(error.localizedDescription))
            }
        }
    }

    private func downloadModel(_ model: WhisperModel) {
        guard models.downloading == nil else { return }
        modelState = .downloading(model, 0)
        models.onProgress = { [weak self] progress in
            self?.modelState = .downloading(model, Int(progress * 100))
        }
        models.download(model) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if Settings.modelID == model.id { self.loadSelectedModel() }
            case .failure(let error):
                self.modelState = .downloadFailed(error.localizedDescription)
                self.hud.show(.message(L10n.t("model.download_failed")))
            }
        }
    }

    /// Standard app menu so ⌘Q, ⌘W, ⌘C work while the app is in the Dock.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("mainmenu.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("mainmenu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L10n.t("mainmenu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem(title: "Vaulto Note", action: nil, keyEquivalent: "")
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        let editMenu = NSMenu(title: L10n.t("mainmenu.edit"))
        editMenu.addItem(withTitle: L10n.t("mainmenu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("mainmenu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("mainmenu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem(title: L10n.t("mainmenu.edit"), action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        main.addItem(editMenuItem)

        let windowMenu = NSMenu(title: L10n.t("mainmenu.window"))
        windowMenu.addItem(withTitle: L10n.t("mainmenu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L10n.t("mainmenu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowMenuItem = NSMenuItem(title: L10n.t("mainmenu.window"), action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        main.addItem(windowMenuItem)

        return main
    }

    // MARK: - Dictation

    private func startRecording() {
        guard case .idle = phase else { return }
        guard isModelReady else {
            hud.show(.message(modelState.text))
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            hud.show(.message(L10n.t("error.no_mic_access")))
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
                    self.hud.show(.message(L10n.t("error.no_speech")))
                    return
                }
                self.history.add(HistoryEntry(
                    date: Date(),
                    text: transcript.text,
                    language: transcript.language,
                    audioSeconds: transcript.audioSeconds
                ))
                self.status.history = self.history.entries
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

        menu.addItem(disabledItem(modelState.text))
        if !TextInserter.isTrusted {
            menu.addItem(item(L10n.t("menu.allow_accessibility"), #selector(openAccessibility)))
        }
        menu.addItem(disabledItem(L10n.t("menu.hold_to_speak", Settings.triggerKey.title)))

        let recordTitle: String
        if case .recording = phase {
            recordTitle = L10n.t("menu.stop_insert")
        } else {
            recordTitle = L10n.t("menu.start_recording")
        }
        menu.addItem(item(recordTitle, #selector(toggleRecording)))
        menu.addItem(.separator())

        let historyMenu = NSMenu()
        if history.entries.isEmpty {
            historyMenu.addItem(disabledItem(L10n.t("menu.history_empty")))
        } else {
            for (index, entry) in history.entries.prefix(15).enumerated() {
                let title = entry.text.count > 60 ? String(entry.text.prefix(60)) + "…" : entry.text
                let historyItem = item(title, #selector(copyHistoryEntry(_:)))
                historyItem.tag = index
                historyItem.toolTip = entry.text
                historyMenu.addItem(historyItem)
            }
            historyMenu.addItem(.separator())
            historyMenu.addItem(disabledItem(L10n.t("menu.click_to_copy")))
            historyMenu.addItem(item(L10n.t("menu.clear_history"), #selector(clearHistory)))
        }
        menu.addItem(submenu(L10n.t("menu.history"), historyMenu))

        let languageMenu = NSMenu()
        for (index, language) in DictationLanguage.all.enumerated() {
            let languageItem = item(language.title, #selector(selectLanguage(_:)))
            languageItem.tag = index
            languageItem.state = language.code == Settings.language ? .on : .off
            languageMenu.addItem(languageItem)
        }
        menu.addItem(submenu(L10n.t("settings.speech_language"), languageMenu))

        let interfaceMenu = NSMenu()
        let systemItem = item(L10n.t("lang.system", L10n.name(of: L10n.systemLanguage)), #selector(selectInterfaceLanguage(_:)))
        systemItem.representedObject = "system"
        interfaceMenu.addItem(systemItem)
        interfaceMenu.addItem(.separator())
        for language in L10n.languages {
            let languageItem = item(language.name, #selector(selectInterfaceLanguage(_:)))
            languageItem.representedObject = language.code
            interfaceMenu.addItem(languageItem)
        }
        for languageItem in interfaceMenu.items {
            languageItem.state = languageItem.representedObject as? String == Settings.interfaceLanguage ? .on : .off
        }
        menu.addItem(submenu(L10n.t("settings.interface_language"), interfaceMenu))

        let keyMenu = NSMenu()
        for (index, key) in TriggerKey.allCases.enumerated() {
            let keyItem = item(key.title, #selector(selectTriggerKey(_:)))
            keyItem.tag = index
            keyItem.state = key == Settings.triggerKey ? .on : .off
            keyMenu.addItem(keyItem)
        }
        menu.addItem(submenu(L10n.t("settings.key"), keyMenu))

        let modelMenu = NSMenu()
        for (index, model) in WhisperModel.all.enumerated() {
            let suffix = model.isDownloaded ? "" : L10n.t("model.download_suffix")
            let modelItem = item("\(model.title) (\(model.sizeLabel))\(suffix)", #selector(selectModel(_:)))
            modelItem.tag = index
            modelItem.state = model.id == Settings.modelID ? .on : .off
            modelMenu.addItem(modelItem)
        }
        modelMenu.addItem(.separator())
        modelMenu.addItem(item(L10n.t("menu.open_models_folder"), #selector(openModelsFolder)))
        menu.addItem(submenu(L10n.t("settings.model"), modelMenu))

        let spaceItem = item(L10n.t("settings.trailing_space"), #selector(toggleTrailingSpace))
        spaceItem.state = Settings.trailingSpace ? .on : .off
        menu.addItem(spaceItem)

        menu.addItem(.separator())
        menu.addItem(item(L10n.t("menu.open_window"), #selector(openMainWindow)))
        menu.addItem(item(L10n.t("menu.quit"), #selector(NSApplication.terminate(_:)), key: "q"))
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
        status.history = []
    }

    @objc private func openMainWindow() {
        mainWindow.show()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        setLanguage(DictationLanguage.all[sender.tag].code)
    }

    @objc private func selectTriggerKey(_ sender: NSMenuItem) {
        setTriggerKey(TriggerKey.allCases[sender.tag])
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        setModel(WhisperModel.all[sender.tag])
    }

    @objc private func selectInterfaceLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        setInterfaceLanguage(code)
    }

    private func setInterfaceLanguage(_ code: String) {
        Settings.interfaceLanguage = code
        status.interfaceLanguage = code
        status.modelStatus = modelState.text
        NSApp.mainMenu = Self.makeMainMenu()
    }

    private func setLanguage(_ code: String) {
        Settings.language = code
        status.language = code
    }

    private func setTriggerKey(_ key: TriggerKey) {
        Settings.triggerKey = key
        status.triggerKey = key
        hotkey.key = key
        hotkey.start()
    }

    private func setModel(_ model: WhisperModel) {
        guard models.downloading == nil else {
            hud.show(.message(L10n.t("model.wait_download")))
            return
        }
        Settings.modelID = model.id
        status.modelID = model.id
        loadSelectedModel()
    }

    private func setShowInDock(_ show: Bool) {
        Settings.showInDock = show
        status.showInDock = show
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        // Switching to .accessory hides the window along with the app; keep it on screen.
        DispatchQueue.main.async { self.mainWindow.show() }
    }

    @objc private func openModelsFolder() {
        NSWorkspace.shared.open(AppPaths.models)
    }

    @objc private func toggleTrailingSpace() {
        Settings.trailingSpace.toggle()
        status.trailingSpace = Settings.trailingSpace
    }
}
