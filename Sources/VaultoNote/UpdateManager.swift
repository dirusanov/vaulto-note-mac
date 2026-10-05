import AppKit
import Combine
import Sparkle

/// Holds a requested restart until dictation and model preparation finish.
final class UpdateRestartGate {
    /// One quiet second lets pending paste/clipboard work finish. New activity
    /// cancels this window, including download → model preparation transitions.
    private let scheduleIdle: (@escaping () -> Void) -> (() -> Void)
    private var activityBusy = false
    private var cancelIdle: (() -> Void)?
    private var idleGeneration: UInt = 0

    init(scheduleIdle: @escaping (@escaping () -> Void) -> (() -> Void) = { action in
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        return { work.cancel() }
    }) {
        self.scheduleIdle = scheduleIdle
    }

    var isBusy: Bool {
        get { activityBusy || cancelIdle != nil }
        set {
            activityBusy = newValue
            idleGeneration &+= 1
            cancelIdle?()
            cancelIdle = nil
            guard !newValue else { return }
            let generation = idleGeneration
            cancelIdle = scheduleIdle { [weak self] in
                guard let self, generation == self.idleGeneration, !self.activityBusy else { return }
                self.cancelIdle = nil
                guard let restart = self.pendingRestart else { return }
                self.pendingRestart = nil
                restart()
            }
        }
    }
    private var pendingRestart: (() -> Void)?

    func postpone(_ restart: @escaping () -> Void) -> Bool {
        guard isBusy else { return false }
        pendingRestart = restart
        return true
    }

    func cancel() { pendingRestart = nil }
}

/// The initial Install Update choice is sufficient consent for this session.
/// Keep Sparkle's standard progress/errors, but avoid a second restart button.
final class OneClickUpdateDriver: SPUStandardUserDriver {
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        reply(.install)
    }
}

/// Sparkle owns scheduling, signed downloads, installation and the update UI.
/// Creation is harmless in tests/snapshots; only the normal app starts the updater.
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, NSMenuItemValidation {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates =
        UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true

    @Published private(set) var isStarted = false
    private var updater: SPUUpdater?
    private var subscriptions = Set<AnyCancellable>()
    private let restartGate = UpdateRestartGate()

    func start(app: AppController) {
        guard updater == nil else { return }
        let driver = OneClickUpdateDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                 userDriver: driver, delegate: self)
        self.updater = updater

        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &subscriptions)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &subscriptions)
        Publishers.CombineLatest3(app.$phase, app.$downloadingModelID, app.$modelState)
            .sink { [weak self] phase, download, modelState in
                self?.restartGate.isBusy = phase != .idle || download != nil || modelState == .loading
            }
            .store(in: &subscriptions)
        do {
            try updater.start()
            isStarted = true
        } catch {
            self.updater = nil
            subscriptions.removeAll()
            NSAlert(error: error).runModal()
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        updater?.checkForUpdates()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        restartGate.postpone(installHandler)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        restartGate.cancel()
    }
}
