import AppKit
import AVFoundation
import ServiceManagement

enum Page: String, CaseIterable, Identifiable {
    case home, history, shortcuts, transcription, general
    var id: String { rawValue }
}

/// App state and the dictation pipeline. The window binds to the published settings
/// directly; each setter persists and applies its side effect.
final class AppController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(started: Date)
        case transcribing
    }

    /// Kept as data rather than a string so the text follows interface language changes.
    enum ModelState: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(String)
    }

    let updates = UpdateManager()

    // MARK: Runtime state

    @Published private(set) var phase = Phase.idle
    @Published private(set) var modelState = ModelState.notLoaded
    @Published private(set) var downloadingModelID: String?
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var downloadError: String?
    @Published private(set) var micGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var history: [HistoryEntry] = []
    /// Microphone level 0…1 while recording, for the in-window record button.
    @Published private(set) var level: Float = 0
    /// Text of a dictation started from the window's record button. There is no text
    /// field to paste into then, so it's shown under the button and copied instead.
    @Published private(set) var inAppResult: String?
    private var recordingFromWindow = false
    @Published var page: Page = .home
    /// True while the shortcut recorder listens, so the trigger doesn't fire.
    @Published var isRecordingShortcut = false {
        didSet { hotkey.isSuspended = isRecordingShortcut }
    }

    // MARK: Settings

    @Published var interfaceLanguage = Settings.interfaceLanguage {
        didSet {
            Settings.interfaceLanguage = interfaceLanguage
            onInterfaceLanguageChange?()
        }
    }
    @Published var speechLanguage = Settings.language {
        didSet { Settings.language = speechLanguage }
    }
    @Published var shortcut = Settings.shortcut {
        didSet {
            Settings.shortcut = shortcut
            hotkey.shortcut = shortcut
        }
    }
    @Published var triggerMode = Settings.triggerMode {
        didSet {
            Settings.triggerMode = triggerMode
            hotkey.mode = triggerMode
        }
    }
    @Published var cancelWithEscape = Settings.cancelWithEscape {
        didSet {
            Settings.cancelWithEscape = cancelWithEscape
            hotkey.cancelWithEscape = cancelWithEscape
        }
    }
    @Published var vocabulary = Settings.vocabulary {
        didSet { Settings.vocabulary = vocabulary }
    }
    @Published var autoPaste = Settings.autoPaste {
        didSet { Settings.autoPaste = autoPaste }
    }
    @Published var trailingSpace = Settings.trailingSpace {
        didSet { Settings.trailingSpace = trailingSpace }
    }
    @Published var restoreClipboard = Settings.restoreClipboard {
        didSet { Settings.restoreClipboard = restoreClipboard }
    }
    @Published var playSounds = Settings.playSounds {
        didSet { Settings.playSounds = playSounds }
    }
    @Published var showInDock = Settings.showInDock {
        didSet {
            Settings.showInDock = showInDock
            onDockVisibilityChange?(showInDock)
        }
    }
    @Published private(set) var selectedModelID = Settings.modelID

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                hud.show(.message(error.localizedDescription))
            }
        }
    }

    var onInterfaceLanguageChange: (() -> Void)?
    var onShowOnboarding: (() -> Void)?
    var onDockVisibilityChange: ((Bool) -> Void)?
    /// Called on every phase change so the status bar icon can follow.
    var onPhaseChange: ((Phase) -> Void)?

    // MARK: Parts

    private let engine = WhisperEngine()
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let hud = HUDController()
    private let historyStore = HistoryStore()
    private let models = ModelManager()
    private let pasteLastHotKey = CarbonHotKey(id: 2)
    private var permissionTimer: Timer?

    var selectedModel: WhisperModel { WhisperModel.find(selectedModelID) }
    var isReady: Bool { modelState == .ready && micGranted && accessibilityGranted }

    var statusText: String {
        if let id = downloadingModelID {
            return L10n.t("model.downloading", WhisperModel.find(id).name, Int(downloadProgress * 100))
        }
        switch modelState {
        case .notLoaded:
            return selectedModel.isDownloaded ? L10n.t("model.not_loaded") : L10n.t("model.not_downloaded")
        case .loading: return L10n.t("model.loading")
        case .failed(let message): return message
        case .ready:
            if !micGranted || !accessibilityGranted { return L10n.t("status.needs_permissions") }
            return L10n.t("status.ready")
        }
    }

    // MARK: - Lifecycle

    func start() {
        history = historyStore.entries
        recorder.onLevel = { [weak self] level in
            self?.hud.setLevel(level)
            self?.level = level
        }

        hotkey.shortcut = shortcut
        hotkey.mode = triggerMode
        hotkey.cancelWithEscape = cancelWithEscape
        hotkey.onStart = { [weak self] in self?.startRecording() }
        hotkey.onStop = { [weak self] in self?.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.cancelRecording() }
        hotkey.start()

        pasteLastHotKey.onPress = { [weak self] in self?.pasteLast() }
        pasteLastHotKey.register(keyCode: 9, modifiers: [.control, .command]) // ⌃⌘V

        refreshPermissions()
        // Permissions change in System Settings, outside the app; poll to notice.
        // Prompts are shown only when the user asks (onboarding, Allow buttons).
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
        // A model already on disk loads right away; a first download waits for onboarding
        // so 1.6 GB doesn't start before the user knows what the app is.
        if Settings.onboardingDone || selectedModel.isDownloaded { prepareModel() }
    }

    /// Loads the selected model, downloading it first if needed.
    func prepareModel() {
        guard modelState == .notLoaded, downloadingModelID == nil else { return }
        loadSelectedModel()
    }

    func shutdown() {
        _ = recorder.stop()
        engine.unload()
    }

    func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let trusted = TextInserter.isTrusted
        if mic != micGranted { micGranted = mic }
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
            // Monitors installed before trust was granted stay deaf; reinstall them.
            if trusted { hotkey.start() }
        }
    }

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.refreshPermissions() }
            }
        case .authorized:
            break
        default:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    func requestAccessibility() {
        TextInserter.requestTrust()
        TextInserter.openAccessibilitySettings()
    }

    // MARK: - Models

    func selectModel(_ model: WhisperModel) {
        guard model.id != selectedModelID || modelState != .ready else { return }
        guard model.isDownloaded else {
            download(model)
            return
        }
        selectedModelID = model.id
        Settings.modelID = model.id
        loadSelectedModel()
    }

    func download(_ model: WhisperModel) {
        guard downloadingModelID == nil else { return }
        downloadingModelID = model.id
        downloadProgress = 0
        downloadError = nil
        models.onProgress = { [weak self] in self?.downloadProgress = $0 }
        models.download(model) { [weak self] result in
            guard let self else { return }
            self.downloadingModelID = nil
            switch result {
            case .success:
                // A finished download becomes the active model.
                self.selectedModelID = model.id
                Settings.modelID = model.id
                self.loadSelectedModel()
            case .failure(let error):
                self.downloadError = error.localizedDescription
            }
        }
    }

    func cancelDownload() {
        models.cancel()
        downloadingModelID = nil
    }

    func deleteModel(_ model: WhisperModel) {
        guard model.id != selectedModelID else { return }
        models.delete(model)
        objectWillChange.send()
    }

    private func loadSelectedModel() {
        let model = selectedModel
        guard model.isDownloaded else {
            modelState = .notLoaded
            download(model)
            return
        }
        modelState = .loading
        engine.load(modelPath: model.fileURL.path) { [weak self] result in
            guard let self, self.selectedModelID == model.id else { return }
            switch result {
            case .success: self.modelState = .ready
            case .failure(let error): self.modelState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Dictation

    /// The record button in the main window.
    func toggleRecordingFromWindow() {
        if phase == .idle {
            recordingFromWindow = true
            inAppResult = nil
        }
        toggleRecording()
        if phase == .idle { recordingFromWindow = false }
    }


    func toggleRecording() {
        switch phase {
        case .idle:
            startRecording()
            if phase != .idle { hotkey.lock() }
        case .recording:
            hotkey.reset()
            finishRecording()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        guard phase == .idle else { return }
        guard modelState == .ready else {
            hotkey.reset()
            hud.show(.message(statusText))
            return
        }
        guard micGranted else {
            hotkey.reset()
            hud.show(.message(L10n.t("error.no_mic_access")))
            requestMicrophone()
            return
        }
        do {
            try recorder.start()
            setPhase(.recording(started: Date()))
            // The window's record button shows its own state; the HUD is for other apps.
            if !recordingFromWindow { hud.show(.recording(started: Date())) }
            playSound("Tink")
        } catch {
            hotkey.reset()
            hud.show(.message(error.localizedDescription))
        }
    }

    private func finishRecording() {
        guard case .recording = phase else { return }
        let samples = recorder.stop()
        let fromWindow = recordingFromWindow
        recordingFromWindow = false
        playSound("Pop")
        setPhase(.transcribing)
        if !fromWindow { hud.show(.transcribing) }

        engine.transcribe(samples: samples, language: speechLanguage, prompt: vocabulary) { [weak self] result in
            guard let self else { return }
            // Persist and deliver before telling the updater that dictation is idle.
            defer { self.setPhase(.idle) }
            self.hud.show(.hidden)
            switch result {
            case .success(let transcript):
                guard !transcript.text.isEmpty else {
                    self.hud.show(.message(L10n.t("error.no_speech")))
                    return
                }
                self.historyStore.add(HistoryEntry(
                    date: Date(),
                    text: transcript.text,
                    language: transcript.language,
                    audioSeconds: transcript.audioSeconds
                ))
                self.history = self.historyStore.entries
                self.deliver(transcript.text, fromWindow: fromWindow)
            case .failure(let error):
                self.hud.show(.message(error.localizedDescription))
            }
        }
    }

    private func deliver(_ text: String, fromWindow: Bool) {
        if fromWindow {
            TextInserter.copy(text)
            inAppResult = text
            return
        }
        let output = text + (trailingSpace ? " " : "")
        if autoPaste && accessibilityGranted && TextInserter.hasFocusedTextField {
            TextInserter.insert(output, restoreClipboard: restoreClipboard)
        } else {
            // Nowhere to type into: keep the text on the clipboard rather than lose it.
            TextInserter.copy(output)
            hud.show(.message(autoPaste ? L10n.t("hud.copied_paste") : L10n.t("hud.copied")))
        }
    }

    private func cancelRecording() {
        guard case .recording = phase else { return }
        recordingFromWindow = false
        _ = recorder.stop()
        setPhase(.idle)
        hud.show(.hidden)
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        if phase == .idle { level = 0 }
        onPhaseChange?(phase)
    }

    private func playSound(_ name: String) {
        guard playSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Fills the state with sample data for `--snapshot` renders; nothing is persisted.
    func applyPreviewState(setupDone: Bool) {
        modelState = setupDone ? .ready : .notLoaded
        micGranted = setupDone
        accessibilityGranted = setupDone
        if !setupDone {
            downloadingModelID = WhisperModel.defaultModel.id
            downloadProgress = 0.42
        }
        let now = Date()
        let samples: [(String, String, Double, TimeInterval)] = [
            ("Привет! Нужно задеплоить новый билд на продакшн и проверить, что синхронизация заметок работает.", "ru", 8.4, -300),
            ("Remind me to review the pull request about end-to-end encryption before Friday.", "en", 4.5, -3_600),
            ("Ich muss morgen früh zum Bürgeramt und meine Adresse ummelden.", "de", 3.7, -7_200),
            ("Встреча с командой перенесена на четверг, в три часа. Подготовить демо новой версии для Mac.", "ru", 6.1, -90_000),
            ("Купить молоко, хлеб и кофе.", "ru", 2.2, -95_000),
        ]
        history = setupDone ? samples.map {
            HistoryEntry(date: now.addingTimeInterval($0.3), text: $0.0, language: $0.1, audioSeconds: $0.2)
        } : []
    }

    /// Pastes the latest dictation again (⌃⌘V or the menu).
    func pasteLast() {
        guard let entry = history.first else { return }
        if accessibilityGranted {
            TextInserter.insert(entry.text + (trailingSpace ? " " : ""), restoreClipboard: restoreClipboard)
        } else {
            TextInserter.copy(entry.text)
            hud.show(.message(L10n.t("hud.copied")))
        }
    }

    /// Snapshot-only: shows practice waiting, ready, or failed without network requests.
    func applyPreviewModelState(_ state: ModelState, downloadError: String? = nil) {
        modelState = state
        downloadingModelID = nil
        self.downloadError = downloadError
    }

    /// Snapshot-only: shows the record button mid-recording or with a result.
    func applyPreviewDictation(recording: Bool, result: String?, transcribing: Bool = false,
                               elapsed: TimeInterval = 12, level: Float = 0.5) {
        if transcribing {
            phase = .transcribing
        } else {
            phase = recording ? .recording(started: Date().addingTimeInterval(-elapsed)) : .idle
        }
        self.level = recording ? level : 0
        inAppResult = result
    }

    // MARK: - History

    func copy(_ entry: HistoryEntry) {
        TextInserter.copy(entry.text)
    }

    func delete(_ entry: HistoryEntry) {
        historyStore.delete(entry.id)
        history = historyStore.entries
    }

    func clearHistory() {
        historyStore.clear()
        history = []
    }
}
