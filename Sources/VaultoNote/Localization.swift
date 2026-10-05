import Foundation

/// Interface strings. The language follows macOS (first supported entry of the
/// user's preferred languages) unless picked explicitly in settings; switching it
/// takes effect immediately, without a relaunch.
enum L10n {
    struct Language {
        let code: String
        let name: String // endonym, shown as is in every interface language
    }

    static let languages: [Language] = [
        .init(code: "en", name: "English"),
        .init(code: "ru", name: "Русский"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"),
        .init(code: "pt", name: "Português"),
        .init(code: "zh", name: "中文"),
        .init(code: "ja", name: "日本語"),
    ]

    static let systemLanguage: String = {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier ?? ""
            if languages.contains(where: { $0.code == code }) { return code }
        }
        return "en"
    }()

    /// Active interface language code.
    static var current: String {
        let chosen = Settings.interfaceLanguage
        return chosen == "system" ? systemLanguage : chosen
    }

    static var locale: Locale { Locale(identifier: current) }

    static func name(of code: String) -> String {
        languages.first { $0.code == code }?.name ?? code
    }

    static func t(_ key: String, _ args: CVarArg...) -> String {
        guard let entry = table[key] else {
            assertionFailure("Missing string \(key)")
            return key
        }
        let format = entry[current] ?? entry["en"] ?? key
        return args.isEmpty ? format : String(format: format, locale: locale, arguments: args)
    }

    /// "1.6 GB" / "1,6 ГБ" with the decimal separator of the interface language.
    static func size(gigabytes: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.maximumFractionDigits = 1
        if gigabytes < 1 {
            return t("unit.mb", formatter.string(from: NSNumber(value: (gigabytes * 1000).rounded())) ?? "")
        }
        return t("unit.gb", formatter.string(from: NSNumber(value: gigabytes)) ?? "")
    }

    // Columns: en, ru, de, es, fr, pt, zh, ja.
    private static func row(_ values: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(languages.map(\.code), values))
    }

    private static let table: [String: [String: String]] = [
        // Units
        "unit.gb": row(["%@ GB", "%@ ГБ", "%@ GB", "%@ GB", "%@ Go", "%@ GB", "%@ GB", "%@ GB"]),
        "unit.mb": row(["%@ MB", "%@ МБ", "%@ MB", "%@ MB", "%@ Mo", "%@ MB", "%@ MB", "%@ MB"]),
        "unit.seconds": row(["%d s", "%d с", "%d s", "%d s", "%d s", "%d s", "%d 秒", "%d 秒"]),

        // Model state
        "model.not_loaded": row([
            "Model not loaded", "Модель не загружена", "Modell nicht geladen", "Modelo no cargado",
            "Modèle non chargé", "Modelo não carregado", "模型未加载", "モデル未読み込み",
        ]),
        "model.not_downloaded": row([
            "Model not downloaded", "Модель не скачана", "Modell nicht heruntergeladen", "Modelo no descargado",
            "Modèle non téléchargé", "Modelo não baixado", "模型未下载", "モデル未ダウンロード",
        ]),
        "model.loading": row([
            "Loading model…", "Загружаю модель…", "Modell wird geladen…", "Cargando modelo…",
            "Chargement du modèle…", "Carregando modelo…", "正在加载模型…", "モデルを読み込み中…",
        ]),
        "model.ready": row([
            "%@ — ready", "%@ — готово", "%@ — bereit", "%@ — listo",
            "%@ — prêt", "%@ — pronto", "%@ — 就绪", "%@ — 準備完了",
        ]),
        "model.downloading": row([
            "Downloading %@… %d%%", "Скачиваю %@… %d%%", "Lade %@ herunter… %d%%", "Descargando %@… %d%%",
            "Téléchargement de %@… %d%%", "Baixando %@… %d%%", "正在下载 %@… %d%%", "%@ をダウンロード中… %d%%",
        ]),
        "model.download_error": row([
            "Download failed: %@", "Ошибка загрузки: %@", "Download fehlgeschlagen: %@", "Error de descarga: %@",
            "Échec du téléchargement : %@", "Falha no download: %@", "下载失败：%@", "ダウンロード失敗：%@",
        ]),
        "model.download_failed": row([
            "Couldn't download the model", "Не удалось скачать модель", "Modell konnte nicht geladen werden",
            "No se pudo descargar el modelo", "Impossible de télécharger le modèle", "Não foi possível baixar o modelo",
            "无法下载模型", "モデルをダウンロードできませんでした",
        ]),
        "model.wait_download": row([
            "Wait for the download to finish", "Дождитесь окончания загрузки", "Warten Sie, bis der Download fertig ist",
            "Espera a que termine la descarga", "Attendez la fin du téléchargement", "Aguarde o fim do download",
            "请等待下载完成", "ダウンロードの完了をお待ちください",
        ]),
        "model.download_suffix": row([
            " — download", " — скачать", " — herunterladen", " — descargar",
            " — télécharger", " — baixar", " — 下载", " — ダウンロード",
        ]),
        "model.compressed": row([
            "compressed", "сжатая", "komprimiert", "comprimido", "compressé", "comprimido", "压缩版", "圧縮版",
        ]),

        // Errors
        "error.no_mic_access": row([
            "No microphone access", "Нет доступа к микрофону", "Kein Mikrofonzugriff", "Sin acceso al micrófono",
            "Pas d'accès au micro", "Sem acesso ao microfone", "无法访问麦克风", "マイクへのアクセスがありません",
        ]),
        "error.mic_unavailable": row([
            "Microphone unavailable", "Микрофон недоступен", "Mikrofon nicht verfügbar", "Micrófono no disponible",
            "Micro indisponible", "Microfone indisponível", "麦克风不可用", "マイクが使用できません",
        ]),
        "error.no_speech": row([
            "No speech recognized", "Речь не распознана", "Keine Sprache erkannt", "No se reconoció voz",
            "Aucune parole reconnue", "Nenhuma fala reconhecida", "未识别到语音", "音声を認識できませんでした",
        ]),
        "error.model_not_loaded": row([
            "Model not loaded", "Модель не загружена", "Modell nicht geladen", "Modelo no cargado",
            "Modèle non chargé", "Modelo não carregado", "模型未加载", "モデル未読み込み",
        ]),
        "error.load_failed": row([
            "Couldn't load the model: %@", "Не удалось загрузить модель: %@", "Modell konnte nicht geladen werden: %@",
            "No se pudo cargar el modelo: %@", "Impossible de charger le modèle : %@", "Não foi possível carregar o modelo: %@",
            "无法加载模型：%@", "モデルを読み込めませんでした：%@",
        ]),
        "error.transcription_failed": row([
            "Transcription error (code %d)", "Ошибка распознавания (код %d)", "Transkriptionsfehler (Code %d)",
            "Error de transcripción (código %d)", "Erreur de transcription (code %d)", "Erro de transcrição (código %d)",
            "转写错误（代码 %d）", "文字起こしエラー（コード %d）",
        ]),
        "error.http": row([
            "The model server answered HTTP %d", "Сервер моделей ответил HTTP %d", "Der Modellserver antwortete mit HTTP %d",
            "El servidor de modelos respondió HTTP %d", "Le serveur de modèles a répondu HTTP %d",
            "O servidor de modelos respondeu HTTP %d", "模型服务器返回 HTTP %d", "モデルサーバーの応答：HTTP %d",
        ]),
        "error.not_a_model": row([
            "The downloaded file is not a Whisper model", "Скачанный файл не является моделью Whisper",
            "Die heruntergeladene Datei ist kein Whisper-Modell", "El archivo descargado no es un modelo Whisper",
            "Le fichier téléchargé n'est pas un modèle Whisper", "O arquivo baixado não é um modelo Whisper",
            "下载的文件不是 Whisper 模型", "ダウンロードしたファイルは Whisper モデルではありません",
        ]),

        // HUD
        "hud.listening": row([
            "Listening…", "Слушаю…", "Höre zu…", "Escuchando…", "J'écoute…", "Ouvindo…", "正在聆听…", "聞き取り中…",
        ]),
        "hud.transcribing": row([
            "Transcribing…", "Распознаю…", "Erkenne…", "Transcribiendo…", "Transcription…", "Transcrevendo…",
            "正在识别…", "認識中…",
        ]),
        "hud.ready_hold": row([
            "Ready: hold %@ and speak", "Готово: удерживайте %@ и говорите", "Bereit: %@ halten und sprechen",
            "Listo: mantén %@ y habla", "Prêt : maintenez %@ et parlez", "Pronto: segure %@ e fale",
            "就绪：按住 %@ 说话", "準備完了：%@ を押しながら話してください",
        ]),

        // Trigger keys
        "key.right_option": row([
            "Right ⌥ Option", "Правый ⌥ Option", "Rechte ⌥ Wahltaste", "⌥ Opción derecha",
            "⌥ Option droite", "⌥ Option direita", "右 ⌥ Option", "右 ⌥ Option",
        ]),
        "key.right_command": row([
            "Right ⌘ Command", "Правый ⌘ Command", "Rechte ⌘ Befehlstaste", "⌘ Comando derecha",
            "⌘ Commande droite", "⌘ Command direita", "右 ⌘ Command", "右 ⌘ Command",
        ]),
        "key.fn": row(["Fn / 🌐", "Fn / 🌐", "Fn / 🌐", "Fn / 🌐", "Fn / 🌐", "Fn / 🌐", "Fn / 🌐", "Fn / 🌐"]),

        // Languages
        "lang.auto": row([
            "Auto-detect", "Автоопределение", "Automatisch erkennen", "Detección automática",
            "Détection automatique", "Detecção automática", "自动检测", "自動検出",
        ]),
        "lang.system": row([
            "System (%@)", "Как в системе (%@)", "Wie im System (%@)", "Como el sistema (%@)",
            "Comme le système (%@)", "Como o sistema (%@)", "跟随系统（%@）", "システムと同じ（%@）",
        ]),

        // Status bar menu
        "menu.allow_accessibility": row([
            "⚠️ Allow Accessibility…", "⚠️ Разрешить Универсальный доступ…", "⚠️ Bedienungshilfen erlauben…",
            "⚠️ Permitir Accesibilidad…", "⚠️ Autoriser l'Accessibilité…", "⚠️ Permitir Acessibilidade…",
            "⚠️ 允许辅助功能…", "⚠️ アクセシビリティを許可…",
        ]),
        "menu.hold_to_speak": row([
            "Hold %@ and speak", "Удерживайте %@ и говорите", "%@ halten und sprechen", "Mantén %@ y habla",
            "Maintenez %@ et parlez", "Segure %@ e fale", "按住 %@ 说话", "%@ を押しながら話す",
        ]),
        "menu.stop_insert": row([
            "Stop and insert", "Остановить и вставить", "Stoppen und einfügen", "Detener e insertar",
            "Arrêter et insérer", "Parar e inserir", "停止并插入", "停止して挿入",
        ]),
        "menu.start_recording": row([
            "Start recording", "Начать запись", "Aufnahme starten", "Empezar a grabar",
            "Commencer l'enregistrement", "Começar a gravar", "开始录音", "録音を開始",
        ]),
        "menu.history": row([
            "History", "История", "Verlauf", "Historial", "Historique", "Histórico", "历史记录", "履歴",
        ]),
        "menu.history_empty": row([
            "Nothing yet", "Пока пусто", "Noch leer", "Aún vacío", "Rien pour l'instant", "Nada ainda", "暂无内容", "まだありません",
        ]),
        "menu.click_to_copy": row([
            "Click an entry to copy it", "Нажмите на запись, чтобы скопировать", "Zum Kopieren auf einen Eintrag klicken",
            "Haz clic en una entrada para copiarla", "Cliquez sur une entrée pour la copier", "Clique em um item para copiá-lo",
            "点击条目即可复制", "項目をクリックしてコピー",
        ]),
        "menu.clear_history": row([
            "Clear history", "Очистить историю", "Verlauf löschen", "Borrar historial",
            "Effacer l'historique", "Limpar histórico", "清除历史记录", "履歴を消去",
        ]),
        "menu.open_models_folder": row([
            "Open models folder", "Открыть папку с моделями", "Modellordner öffnen", "Abrir carpeta de modelos",
            "Ouvrir le dossier des modèles", "Abrir pasta de modelos", "打开模型文件夹", "モデルフォルダを開く",
        ]),
        "menu.open_window": row([
            "Open Vaulto Note window", "Открыть окно Vaulto Note", "Vaulto Note-Fenster öffnen", "Abrir ventana de Vaulto Note",
            "Ouvrir la fenêtre Vaulto Note", "Abrir janela do Vaulto Note", "打开 Vaulto Note 窗口", "Vaulto Note ウインドウを開く",
        ]),
        "menu.quit": row([
            "Quit", "Выйти", "Beenden", "Salir", "Quitter", "Sair", "退出", "終了",
        ]),

        // Settings (shared by the menu and the window)
        "settings.title": row([
            "Settings", "Настройки", "Einstellungen", "Ajustes", "Réglages", "Ajustes", "设置", "設定",
        ]),
        "settings.interface_language": row([
            "Interface language", "Язык интерфейса", "Sprache der Oberfläche", "Idioma de la interfaz",
            "Langue de l'interface", "Idioma da interface", "界面语言", "表示言語",
        ]),
        "settings.speech_language": row([
            "Speech language", "Язык речи", "Sprache der Sprache", "Idioma del habla",
            "Langue parlée", "Idioma da fala", "语音语言", "音声の言語",
        ]),
        "settings.key": row([
            "Key", "Клавиша", "Taste", "Tecla", "Touche", "Tecla", "按键", "キー",
        ]),
        "settings.model": row([
            "Model", "Модель", "Modell", "Modelo", "Modèle", "Modelo", "模型", "モデル",
        ]),
        "settings.trailing_space": row([
            "Space after text", "Пробел после текста", "Leerzeichen nach dem Text", "Espacio después del texto",
            "Espace après le texte", "Espaço após o texto", "文本后加空格", "テキストの後にスペース",
        ]),
        "settings.dock_icon": row([
            "Dock icon", "Иконка в Dock", "Symbol im Dock", "Icono en el Dock",
            "Icône dans le Dock", "Ícone no Dock", "在程序坞中显示图标", "Dock にアイコンを表示",
        ]),

        // Main window
        "window.permissions_needed": row([
            "Permissions needed", "Нужны разрешения", "Berechtigungen erforderlich", "Se necesitan permisos",
            "Autorisations requises", "Permissões necessárias", "需要权限", "許可が必要です",
        ]),
        "window.allow": row([
            "Allow", "Разрешить", "Erlauben", "Permitir", "Autoriser", "Permitir", "允许", "許可",
        ]),
        "window.mic": row([
            "Microphone", "Микрофон", "Mikrofon", "Micrófono", "Micro", "Microfone", "麦克风", "マイク",
        ]),
        "window.mic_detail": row([
            "To hear your speech", "Чтобы слышать речь", "Um Ihre Sprache zu hören", "Para escuchar tu voz",
            "Pour entendre votre voix", "Para ouvir sua fala", "用于听取语音", "音声を聞き取るため",
        ]),
        "window.accessibility": row([
            "Accessibility", "Универсальный доступ", "Bedienungshilfen", "Accesibilidad",
            "Accessibilité", "Acessibilidade", "辅助功能", "アクセシビリティ",
        ]),
        "window.accessibility_detail": row([
            "To catch the key in other apps and paste the text",
            "Чтобы ловить клавишу в других приложениях и вставлять текст",
            "Um die Taste in anderen Apps zu erkennen und Text einzufügen",
            "Para detectar la tecla en otras apps y pegar el texto",
            "Pour détecter la touche dans d'autres apps et coller le texte",
            "Para detectar a tecla em outros apps e colar o texto",
            "用于在其他应用中捕获按键并粘贴文本",
            "他のアプリでキーを検出し、テキストを貼り付けるため",
        ]),
        "window.howto_title": row([
            "How to use", "Как пользоваться", "So funktioniert's", "Cómo usarlo",
            "Mode d'emploi", "Como usar", "使用方法", "使い方",
        ]),
        // %@ is the key name, drawn bold in the window.
        "window.howto_body": row([
            "Put the cursor in any field, hold %@ and speak. Release — the text appears in the field.",
            "Поставьте курсор в любое поле, удерживайте %@ и говорите. Отпустите — текст появится в поле.",
            "Setzen Sie den Cursor in ein Feld, halten Sie %@ und sprechen Sie. Loslassen — der Text erscheint im Feld.",
            "Coloca el cursor en cualquier campo, mantén %@ y habla. Suelta y el texto aparecerá en el campo.",
            "Placez le curseur dans un champ, maintenez %@ et parlez. Relâchez : le texte apparaît dans le champ.",
            "Coloque o cursor em qualquer campo, segure %@ e fale. Solte e o texto aparecerá no campo.",
            "将光标放在任意输入框中，按住 %@ 说话。松开后文本就会出现在输入框中。",
            "任意の入力欄にカーソルを置き、%@ を押しながら話します。離すとテキストが入力されます。",
        ]),
        "window.howto_note": row([
            "A short tap or the key combined with a letter doesn't start recording.",
            "Короткое нажатие или клавиша вместе с буквой не запускают запись.",
            "Ein kurzes Tippen oder die Taste zusammen mit einem Buchstaben startet keine Aufnahme.",
            "Una pulsación corta o la tecla junto con una letra no inician la grabación.",
            "Un appui bref ou la touche combinée à une lettre ne lance pas l'enregistrement.",
            "Um toque curto ou a tecla junto com uma letra não iniciam a gravação.",
            "短按或与字母键组合按下不会开始录音。",
            "短く押した場合や文字キーと組み合わせた場合は録音しません。",
        ]),
        "window.history": row([
            "History", "История", "Verlauf", "Historial", "Historique", "Histórico", "历史记录", "履歴",
        ]),
        "window.clear": row([
            "Clear", "Очистить", "Löschen", "Borrar", "Effacer", "Limpar", "清除", "消去",
        ]),
        "window.history_empty": row([
            "Your dictations will appear here", "Здесь появятся ваши диктовки", "Hier erscheinen Ihre Diktate",
            "Aquí aparecerán tus dictados", "Vos dictées apparaîtront ici", "Seus ditados aparecerão aqui",
            "你的听写内容会显示在这里", "ここに音声入力の履歴が表示されます",
        ]),
        "window.copy": row([
            "Copy", "Скопировать", "Kopieren", "Copiar", "Copier", "Copiar", "复制", "コピー",
        ]),

        // Main menu
        "mainmenu.about": row([
            "About Vaulto Note", "О Vaulto Note", "Über Vaulto Note", "Acerca de Vaulto Note",
            "À propos de Vaulto Note", "Sobre o Vaulto Note", "关于 Vaulto Note", "Vaulto Note について",
        ]),
        "mainmenu.hide": row([
            "Hide Vaulto Note", "Скрыть Vaulto Note", "Vaulto Note ausblenden", "Ocultar Vaulto Note",
            "Masquer Vaulto Note", "Ocultar Vaulto Note", "隐藏 Vaulto Note", "Vaulto Note を隠す",
        ]),
        "mainmenu.quit": row([
            "Quit Vaulto Note", "Завершить Vaulto Note", "Vaulto Note beenden", "Salir de Vaulto Note",
            "Quitter Vaulto Note", "Encerrar Vaulto Note", "退出 Vaulto Note", "Vaulto Note を終了",
        ]),
        "mainmenu.edit": row([
            "Edit", "Правка", "Bearbeiten", "Edición", "Édition", "Editar", "编辑", "編集",
        ]),
        "mainmenu.copy": row([
            "Copy", "Скопировать", "Kopieren", "Copiar", "Copier", "Copiar", "拷贝", "コピー",
        ]),
        "mainmenu.paste": row([
            "Paste", "Вставить", "Einsetzen", "Pegar", "Coller", "Colar", "粘贴", "ペースト",
        ]),
        "mainmenu.select_all": row([
            "Select All", "Выбрать все", "Alles auswählen", "Seleccionar todo",
            "Tout sélectionner", "Selecionar tudo", "全选", "すべてを選択",
        ]),
        "mainmenu.window": row([
            "Window", "Окно", "Fenster", "Ventana", "Fenêtre", "Janela", "窗口", "ウインドウ",
        ]),
        "mainmenu.close": row([
            "Close", "Закрыть", "Schließen", "Cerrar", "Fermer", "Fechar", "关闭", "閉じる",
        ]),
        "mainmenu.minimize": row([
            "Minimize", "Свернуть", "Im Dock ablegen", "Minimizar", "Placer dans le Dock", "Minimizar", "最小化", "しまう",
        ]),
    ]
}
