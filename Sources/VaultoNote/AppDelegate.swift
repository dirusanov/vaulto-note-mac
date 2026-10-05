import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let app = AppController()
    private lazy var mainWindow = MainWindowController(app: app)
    private lazy var onboarding = OnboardingWindowController(app: app) { [weak self] in
        self?.mainWindow.show(page: .home)
    }
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon(.idle)

        app.onPhaseChange = { [weak self] in self?.updateIcon($0) }
        app.onInterfaceLanguageChange = { NSApp.mainMenu = Self.makeMainMenu() }
        app.onDockVisibilityChange = { [weak self] show in
            NSApp.setActivationPolicy(show ? .regular : .accessory)
            // Switching to .accessory hides the window along with the app; keep it on screen.
            DispatchQueue.main.async { self?.mainWindow.show() }
        }
        app.onShowOnboarding = { [weak self] in self?.onboarding.show() }
        app.start()

        if !Settings.onboardingDone {
            onboarding.show()
        } else if !Self.launchedAsLoginItem {
            mainWindow.show()
        }
    }

    /// Started by "Open at login": stay quietly in the menu bar.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Clicking the app in Finder, Spotlight or the Dock while it runs brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Settings.onboardingDone { mainWindow.show() } else { onboarding.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        app.shutdown()
    }

    private func updateIcon(_ phase: AppController.Phase) {
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

    // MARK: - Status bar menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(app.statusText))
        if app.isReady {
            menu.addItem(disabledItem(L10n.t("menu.hold_to_speak", app.shortcut.inlineTitle)))
        }
        let recordTitle = app.phase == .idle ? L10n.t("menu.start_recording") : L10n.t("menu.stop_insert")
        menu.addItem(item(recordTitle, #selector(toggleRecording)))
        if !app.history.isEmpty {
            let pasteItem = item(L10n.t("shortcut.paste_last"), #selector(pasteLast))
            pasteItem.keyEquivalent = "v"
            pasteItem.keyEquivalentModifierMask = [.control, .command]
            menu.addItem(pasteItem)
        }

        if !app.history.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabledItem(L10n.t("home.recent")))
            for entry in app.history.prefix(5) {
                let title = entry.text.count > 50 ? String(entry.text.prefix(50)) + "…" : entry.text
                let historyItem = item(title, #selector(copyHistoryEntry(_:)))
                historyItem.representedObject = entry.id
                historyItem.toolTip = L10n.t("menu.click_to_copy")
                menu.addItem(historyItem)
            }
        }

        menu.addItem(.separator())
        let languageMenu = NSMenu()
        for language in DictationLanguage.all {
            let languageItem = item(language.title, #selector(selectSpeechLanguage(_:)))
            languageItem.representedObject = language.code
            languageItem.state = language.code == app.speechLanguage ? .on : .off
            languageMenu.addItem(languageItem)
        }
        let languageItem = NSMenuItem(title: L10n.t("settings.speech_language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(.separator())
        menu.addItem(item(L10n.t("menu.open_window"), #selector(openMainWindow), key: "o"))
        menu.addItem(item(L10n.t("menu.settings"), #selector(openSettings), key: ","))
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

    @objc private func toggleRecording() {
        // Give the menu time to close so the paste lands in the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.app.toggleRecording() }
    }

    @objc private func pasteLast() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.app.pasteLast() }
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let entry = app.history.first(where: { $0.id == id }) else { return }
        app.copy(entry)
    }

    @objc private func selectSpeechLanguage(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { app.speechLanguage = code }
    }

    @objc private func openMainWindow() {
        mainWindow.show(page: .home)
    }

    @objc private func openSettings() {
        mainWindow.show(page: .shortcuts)
    }

    // MARK: - Main menu

    /// Standard app menu so ⌘Q, ⌘W, ⌘C work while the app is in the Dock.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("mainmenu.about"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("mainmenu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L10n.t("mainmenu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenuItem("Vaulto Note", appMenu))

        let editMenu = NSMenu(title: L10n.t("mainmenu.edit"))
        editMenu.addItem(withTitle: L10n.t("mainmenu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("mainmenu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("mainmenu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("mainmenu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("mainmenu.select_all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenuItem(L10n.t("mainmenu.edit"), editMenu))

        let windowMenu = NSMenu(title: L10n.t("mainmenu.window"))
        windowMenu.addItem(withTitle: L10n.t("mainmenu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L10n.t("mainmenu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenuItem(L10n.t("mainmenu.window"), windowMenu))

        return main
    }

    private static func submenuItem(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
