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

    /// Forces a language without touching saved settings (snapshot renders).
    static var override: String?

    /// Active interface language code.
    static var current: String {
        if let override { return override }
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
        "model.downloading": row([
            "Downloading %@… %d%%", "Скачиваю %@… %d%%", "Lade %@ herunter… %d%%", "Descargando %@… %d%%",
            "Téléchargement de %@… %d%%", "Baixando %@… %d%%", "正在下载 %@… %d%%", "%@ をダウンロード中… %d%%",
        ]),
        "model.download_error": row([
            "Download failed: %@", "Ошибка загрузки: %@", "Download fehlgeschlagen: %@", "Error de descarga: %@",
            "Échec du téléchargement : %@", "Falha no download: %@", "下载失败：%@", "ダウンロード失敗：%@",
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
        "menu.click_to_copy": row([
            "Click an entry to copy it", "Нажмите на запись, чтобы скопировать", "Zum Kopieren auf einen Eintrag klicken",
            "Haz clic en una entrada para copiarla", "Cliquez sur une entrée pour la copier", "Clique em um item para copiá-lo",
            "点击条目即可复制", "項目をクリックしてコピー",
        ]),
        "menu.clear_history": row([
            "Clear history", "Очистить историю", "Verlauf löschen", "Borrar historial",
            "Effacer l'historique", "Limpar histórico", "清除历史记录", "履歴を消去",
        ]),
        "menu.open_window": row([
            "Open Vaulto Note window", "Открыть окно Vaulto Note", "Vaulto Note-Fenster öffnen", "Abrir ventana de Vaulto Note",
            "Ouvrir la fenêtre Vaulto Note", "Abrir janela do Vaulto Note", "打开 Vaulto Note 窗口", "Vaulto Note ウインドウを開く",
        ]),
        "menu.quit": row([
            "Quit", "Выйти", "Beenden", "Salir", "Quitter", "Sair", "退出", "終了",
        ]),

        "settings.interface_language": row([
            "Interface language", "Язык интерфейса", "Sprache der Oberfläche", "Idioma de la interfaz",
            "Langue de l'interface", "Idioma da interface", "界面语言", "表示言語",
        ]),
        "settings.speech_language": row([
            "Speech language", "Язык речи", "Sprache der Sprache", "Idioma del habla",
            "Langue parlée", "Idioma da fala", "语音语言", "音声の言語",
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

        // Redesign: pages, shortcuts, models, output, history, general
        "common.recommended": row([
            "Recommended", "Рекомендуем", "Empfohlen", "Recomendado", "Recommandé", "Recomendado", "推荐", "おすすめ",
        ]),
        "status.ready": row([
            "Ready to dictate", "Готово к диктовке", "Bereit zum Diktieren", "Listo para dictar", "Prêt à dicter", "Pronto para ditar", "可以开始听写", "音声入力の準備完了",
        ]),
        "status.needs_permissions": row([
            "Permissions needed", "Нужны разрешения", "Berechtigungen nötig", "Faltan permisos", "Autorisations requises", "Faltam permissões", "需要权限", "許可が必要です",
        ]),
        "page.home": row([
            "Overview", "Обзор", "Übersicht", "Inicio", "Aperçu", "Visão geral", "概览", "概要",
        ]),
        "page.shortcuts": row([
            "Shortcuts", "Горячие клавиши", "Kurzbefehle", "Atajos", "Raccourcis", "Atalhos", "快捷键", "ショートカット",
        ]),
        "page.transcription": row([
            "Transcription", "Распознавание", "Erkennung", "Transcripción", "Transcription", "Transcrição", "识别", "文字起こし",
        ]),
        "page.output": row([
            "Text insertion", "Вставка текста", "Texteinfügen", "Inserción de texto", "Insertion du texte", "Inserção de texto", "文本插入", "テキスト入力",
        ]),
        "page.history": row([
            "History", "История", "Verlauf", "Historial", "Historique", "Histórico", "历史记录", "履歴",
        ]),
        "page.general": row([
            "General", "Основные", "Allgemein", "General", "Général", "Geral", "通用", "一般",
        ]),
        "home.hero_title": row([
            "Speak — Vaulto types", "Говорите — Vaulto напечатает", "Sprechen Sie — Vaulto tippt", "Habla y Vaulto escribe", "Parlez, Vaulto écrit", "Fale e o Vaulto digita", "说话，Vaulto 帮你打字", "話すだけで Vaulto が入力",
        ]),
        "home.change_shortcut": row([
            "Change shortcut", "Изменить клавишу", "Kurzbefehl ändern", "Cambiar atajo", "Modifier le raccourci", "Alterar atalho", "更改快捷键", "ショートカットを変更",
        ]),
        "home.try_title": row([
            "Try it here", "Попробуйте здесь", "Hier ausprobieren", "Pruébalo aquí", "Essayez ici", "Experimente aqui", "在这里试试", "ここで試す",
        ]),
        "home.try_placeholder": row([
            "Click here, hold %@ and say something…", "Нажмите сюда, удерживайте %@ и скажите что-нибудь…", "Hier klicken, %@ halten und etwas sagen…", "Haz clic aquí, mantén %@ y di algo…", "Cliquez ici, maintenez %@ et dites quelque chose…", "Clique aqui, segure %@ e diga algo…", "点击这里，按住 %@ 说点什么…", "ここをクリックし、%@ を押しながら話してみてください…",
        ]),
        "home.stat_dictations": row([
            "Dictations", "Диктовок", "Diktate", "Dictados", "Dictées", "Ditados", "听写次数", "音声入力",
        ]),
        "home.stat_words": row([
            "Words", "Слов", "Wörter", "Palabras", "Mots", "Palavras", "字词", "単語",
        ]),
        "home.stat_minutes": row([
            "Minutes of speech", "Минут речи", "Minuten Sprache", "Minutos de voz", "Minutes de parole", "Minutos de fala", "语音分钟", "話した分数",
        ]),
        "home.recent": row([
            "Recent", "Недавние", "Zuletzt", "Recientes", "Récents", "Recentes", "最近", "最近",
        ]),
        "home.show_all": row([
            "Show all", "Вся история", "Alle anzeigen", "Ver todo", "Tout afficher", "Ver tudo", "查看全部", "すべて表示",
        ]),
        "setup.title": row([
            "Finish setup", "Завершите настройку", "Einrichtung abschließen", "Completa la configuración", "Terminez la configuration", "Conclua a configuração", "完成设置", "セットアップを完了",
        ]),
        "setup.model": row([
            "Model %@", "Модель %@", "Modell %@", "Modelo %@", "Modèle %@", "Modelo %@", "模型 %@", "モデル %@",
        ]),
        "setup.model_detail": row([
            "Downloaded once, then works offline", "Скачивается один раз, дальше работает без интернета", "Einmal laden, danach offline nutzbar", "Se descarga una vez y luego funciona sin conexión", "Téléchargé une fois, puis fonctionne hors ligne", "Baixado uma vez, depois funciona offline", "只需下载一次，之后可离线使用", "一度ダウンロードすればオフラインで動作",
        ]),
        "key.right": row([
            "Right %@", "Правый %@", "Rechts %@", "%@ derecha", "%@ droite", "%@ direita", "右 %@", "右 %@",
        ]),
        "key.right_inline": row([
            "right %@", "правый %@", "rechte %@-Taste", "%@ derecha", "%@ droite", "%@ direita", "右 %@", "右 %@",
        ]),
        "key.space": row([
            "Space", "Пробел", "Leertaste", "Espacio", "Espace", "Espaço", "空格", "スペース",
        ]),
        "shortcut.title": row([
            "Dictation shortcut", "Клавиша диктовки", "Diktier-Kurzbefehl", "Atajo de dictado", "Raccourci de dictée", "Atalho de ditado", "听写快捷键", "音声入力のショートカット",
        ]),
        "shortcut.detail": row([
            "A single key like right ⌥, or a combination like ⌃⌥Space", "Одна клавиша, например правый ⌥, или сочетание вроде ⌃⌥Пробел", "Eine einzelne Taste wie rechts ⌥ oder eine Kombination wie ⌃⌥Leertaste", "Una sola tecla como ⌥ derecha o una combinación como ⌃⌥Espacio", "Une seule touche comme ⌥ droite, ou une combinaison comme ⌃⌥Espace", "Uma tecla como ⌥ direita ou uma combinação como ⌃⌥Espaço", "单个按键（如右 ⌥）或组合键（如 ⌃⌥空格）", "右 ⌥ のような単独キー、または ⌃⌥スペースのような組み合わせ",
        ]),
        "shortcut.presets": row([
            "Quick picks", "Быстрый выбор", "Schnellauswahl", "Opciones rápidas", "Choix rapide", "Escolha rápida", "快速选择", "クイック選択",
        ]),
        "shortcut.press_keys": row([
            "Press keys…", "Нажмите клавиши…", "Tasten drücken…", "Pulsa las teclas…", "Appuyez sur les touches…", "Pressione as teclas…", "请按键…", "キーを押してください…",
        ]),
        "shortcut.click_to_change": row([
            "Click to record a new shortcut; Esc cancels", "Нажмите, чтобы задать новое сочетание; Esc — отмена", "Klicken, um einen neuen Kurzbefehl aufzunehmen; Esc bricht ab", "Haz clic para grabar un atajo nuevo; Esc cancela", "Cliquez pour enregistrer un nouveau raccourci ; Échap annule", "Clique para gravar um novo atalho; Esc cancela", "点击录制新快捷键，按 Esc 取消", "クリックして新しいショートカットを記録（Esc でキャンセル）",
        ]),
        "shortcut.use_right_key": row([
            "Use the right-hand key: the left one is busy with regular shortcuts", "Используйте правую клавишу: левая занята обычными сочетаниями", "Nehmen Sie die rechte Taste: Die linke wird für normale Kurzbefehle gebraucht", "Usa la tecla derecha: la izquierda se usa en atajos normales", "Utilisez la touche de droite : celle de gauche sert aux raccourcis habituels", "Use a tecla da direita: a da esquerda é usada em atalhos comuns", "请使用右侧按键：左侧按键用于常规快捷键", "右側のキーを使ってください（左側は通常のショートカットで使われます）",
        ]),
        "shortcut.add_modifier": row([
            "Add ⌘, ⌥ or ⌃ to the key", "Добавьте к клавише ⌘, ⌥ или ⌃", "Fügen Sie ⌘, ⌥ oder ⌃ hinzu", "Añade ⌘, ⌥ o ⌃ a la tecla", "Ajoutez ⌘, ⌥ ou ⌃ à la touche", "Adicione ⌘, ⌥ ou ⌃ à tecla", "请加上 ⌘、⌥ 或 ⌃", "⌘、⌥、⌃ のいずれかを組み合わせてください",
        ]),
        "shortcut.fn_hint": row([
            "If 🌐 opens emoji or system dictation, set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.", "Если 🌐 открывает эмодзи или системную диктовку: Системные настройки → Клавиатура → «Нажатие клавиши 🌐» → «Ничего не делать».", "Wenn 🌐 Emojis oder das System-Diktat öffnet: Systemeinstellungen → Tastatur → „Drücken der Taste 🌐“ → „Keine Aktion“.", "Si 🌐 abre los emojis o el dictado del sistema: Ajustes del Sistema → Teclado → «Pulsar la tecla 🌐» → «No hacer nada».", "Si 🌐 ouvre les émojis ou la dictée système : Réglages Système → Clavier → « Appuyer sur la touche 🌐 » → « Ne rien faire ».", "Se 🌐 abre emojis ou o ditado do sistema: Ajustes do Sistema → Teclado → “Pressionar a tecla 🌐” → “Não fazer nada”.", "如果 🌐 会打开表情或系统听写：系统设置 → 键盘 → “按下 🌐 键时” → “不执行任何操作”。", "🌐 で絵文字やシステムの音声入力が開く場合：システム設定 → キーボード →「🌐キーを押して」→「何もしない」。",
        ]),
        "shortcut.needs_accessibility": row([
            "A single key works in other apps only with Accessibility allowed (General → Permissions).", "Одиночная клавиша работает в других приложениях только с разрешением «Универсальный доступ» (Основные → Разрешения).", "Eine einzelne Taste funktioniert in anderen Apps nur mit erlaubten Bedienungshilfen (Allgemein → Berechtigungen).", "Una sola tecla funciona en otras apps solo con Accesibilidad permitida (General → Permisos).", "Une touche seule ne fonctionne dans les autres apps qu'avec l'Accessibilité autorisée (Général → Autorisations).", "Uma tecla única só funciona em outros apps com a Acessibilidade permitida (Geral → Permissões).", "单个按键需开启“辅助功能”权限才能在其他应用中使用（通用 → 权限）。", "単独キーを他のアプリで使うにはアクセシビリティの許可が必要です（一般 → 許可）。",
        ]),
        "shortcut.escape": row([
            "Cancel with Esc", "Отмена по Esc", "Mit Esc abbrechen", "Cancelar con Esc", "Annuler avec Échap", "Cancelar com Esc", "按 Esc 取消", "Esc でキャンセル",
        ]),
        "shortcut.escape_detail": row([
            "Discards the recording without inserting anything", "Запись удаляется, ничего не вставляется", "Verwirft die Aufnahme, ohne etwas einzufügen", "Descarta la grabación sin insertar nada", "Abandonne l'enregistrement sans rien insérer", "Descarta a gravação sem inserir nada", "放弃录音，不插入任何内容", "録音を破棄し、何も入力しません",
        ]),
        "mode.title": row([
            "Recording mode", "Режим записи", "Aufnahmemodus", "Modo de grabación", "Mode d'enregistrement", "Modo de gravação", "录音模式", "録音モード",
        ]),
        "mode.hybrid.title": row([
            "Hold or tap", "Удержание или нажатие", "Halten oder tippen", "Mantener o pulsar", "Maintenir ou appuyer", "Segurar ou tocar", "按住或轻点", "長押しまたはタップ",
        ]),
        "mode.hybrid.summary": row([
            "Hold %@ to talk and release to insert. Tap it once for hands-free recording, tap again to finish.", "Удерживайте %@ и говорите, отпустите — текст вставится. Короткое нажатие включает запись без рук, повторное — завершает.", "Halten Sie %@ zum Sprechen und lassen Sie los zum Einfügen. Einmal tippen für freihändige Aufnahme, erneut tippen zum Beenden.", "Mantén %@ para hablar y suelta para insertar. Púlsalo una vez para grabar sin manos y otra vez para terminar.", "Maintenez %@ pour parler et relâchez pour insérer. Appuyez une fois pour enregistrer mains libres, à nouveau pour terminer.", "Segure %@ para falar e solte para inserir. Toque uma vez para gravar sem as mãos e de novo para terminar.", "按住 %@ 说话，松开即插入。轻点一次进入免按住录音，再点一次结束。", "%@ を押しながら話し、離すと入力されます。1回タップでハンズフリー録音、もう一度タップで終了。",
        ]),
        "mode.hold.title": row([
            "Hold to talk", "Только удержание", "Nur halten", "Solo mantener", "Maintenir pour parler", "Segurar para falar", "仅按住", "長押しのみ",
        ]),
        "mode.hold.summary": row([
            "Recording lasts while you hold %@. Short taps are ignored.", "Запись идёт, пока вы держите %@. Короткие нажатия игнорируются.", "Die Aufnahme läuft, solange Sie %@ halten. Kurzes Tippen wird ignoriert.", "Se graba mientras mantienes %@. Las pulsaciones cortas se ignoran.", "L'enregistrement dure tant que vous maintenez %@. Les appuis brefs sont ignorés.", "A gravação dura enquanto você segura %@. Toques curtos são ignorados.", "按住 %@ 期间录音，短按会被忽略。", "%@ を押している間だけ録音します。短いタップは無視されます。",
        ]),
        "mode.toggle.title": row([
            "Press to start and stop", "Нажатие — старт и стоп", "Drücken zum Starten und Stoppen", "Pulsar para iniciar y parar", "Appuyer pour démarrer et arrêter", "Pressionar para iniciar e parar", "按一下开始，再按结束", "押して開始・停止",
        ]),
        "mode.toggle.summary": row([
            "Press %@ to start recording and press it again to insert the text.", "Нажмите %@, чтобы начать запись, и ещё раз, чтобы вставить текст.", "Drücken Sie %@ zum Starten und erneut, um den Text einzufügen.", "Pulsa %@ para empezar a grabar y otra vez para insertar el texto.", "Appuyez sur %@ pour démarrer, puis à nouveau pour insérer le texte.", "Pressione %@ para começar a gravar e de novo para inserir o texto.", "按 %@ 开始录音，再按一次插入文本。", "%@ を押して録音を開始し、もう一度押すとテキストを入力します。",
        ]),
        "model.summary.turbo": row([
            "Fast and accurate, about 100 languages. The best choice for most Macs.", "Быстрая и точная, около 100 языков. Лучший выбор для большинства Mac.", "Schnell und genau, rund 100 Sprachen. Die beste Wahl für die meisten Macs.", "Rápido y preciso, unos 100 idiomas. La mejor opción para la mayoría de los Mac.", "Rapide et précis, environ 100 langues. Le meilleur choix pour la plupart des Mac.", "Rápido e preciso, cerca de 100 idiomas. A melhor escolha para a maioria dos Macs.", "快速准确，支持约 100 种语言。适合大多数 Mac。", "高速かつ高精度で約100言語に対応。ほとんどの Mac に最適です。",
        ]),
        "model.summary.turbo-q5": row([
            "Same model, compressed: three times smaller, slightly less accurate.", "Та же модель в сжатом виде: втрое меньше, чуть менее точная.", "Dasselbe Modell, komprimiert: dreimal kleiner, etwas ungenauer.", "El mismo modelo comprimido: tres veces más pequeño y algo menos preciso.", "Le même modèle compressé : trois fois plus petit, un peu moins précis.", "O mesmo modelo comprimido: três vezes menor e um pouco menos preciso.", "同一模型的压缩版：体积缩小三倍，准确度略低。", "同じモデルの圧縮版。サイズは約3分の1、精度はわずかに低下します。",
        ]),
        "model.summary.large": row([
            "Maximum accuracy for difficult audio and rare languages. Slower and twice as large.", "Максимальная точность для сложной записи и редких языков. Медленнее и вдвое больше.", "Maximale Genauigkeit für schwierige Aufnahmen und seltene Sprachen. Langsamer und doppelt so groß.", "Máxima precisión para audio difícil e idiomas poco comunes. Más lento y el doble de grande.", "Précision maximale pour l'audio difficile et les langues rares. Plus lent et deux fois plus lourd.", "Precisão máxima para áudio difícil e idiomas raros. Mais lento e duas vezes maior.", "针对困难音频和小语种的最高准确度。速度较慢，体积大一倍。", "聞き取りにくい音声や珍しい言語でも最高精度。速度は遅く、サイズは2倍です。",
        ]),
        "model.speed": row([
            "Speed", "Скорость", "Tempo", "Velocidad", "Vitesse", "Velocidade", "速度", "速度",
        ]),
        "model.accuracy": row([
            "Accuracy", "Точность", "Genauigkeit", "Precisión", "Précision", "Precisão", "准确度", "精度",
        ]),
        "model.download": row([
            "Download", "Скачать", "Laden", "Descargar", "Télécharger", "Baixar", "下载", "ダウンロード",
        ]),
        "model.downloaded": row([
            "Downloaded", "Скачана", "Geladen", "Descargado", "Téléchargé", "Baixado", "已下载", "ダウンロード済み",
        ]),
        "model.active": row([
            "In use", "Используется", "Aktiv", "En uso", "Utilisé", "Em uso", "使用中", "使用中",
        ]),
        "model.use": row([
            "Use this model", "Использовать", "Dieses Modell verwenden", "Usar este modelo", "Utiliser ce modèle", "Usar este modelo", "使用此模型", "このモデルを使う",
        ]),
        "model.delete": row([
            "Delete", "Удалить", "Löschen", "Eliminar", "Supprimer", "Excluir", "删除", "削除",
        ]),
        "model.delete_confirm": row([
            "Delete %@ from this Mac?", "Удалить %@ с этого Mac?", "%@ von diesem Mac löschen?", "¿Eliminar %@ de este Mac?", "Supprimer %@ de ce Mac ?", "Excluir %@ deste Mac?", "要从这台 Mac 删除 %@ 吗？", "%@ をこの Mac から削除しますか？",
        ]),
        "model.cancel": row([
            "Cancel download", "Отменить загрузку", "Download abbrechen", "Cancelar descarga", "Annuler le téléchargement", "Cancelar download", "取消下载", "ダウンロードを中止",
        ]),
        "model.private_note": row([
            "Models run entirely on this Mac: audio and text never leave it.", "Модели работают полностью на этом Mac: звук и текст никуда не отправляются.", "Die Modelle laufen vollständig auf diesem Mac: Audio und Text verlassen ihn nie.", "Los modelos funcionan por completo en este Mac: el audio y el texto no salen de él.", "Les modèles tournent entièrement sur ce Mac : l'audio et le texte n'en sortent jamais.", "Os modelos rodam inteiramente neste Mac: áudio e texto nunca saem dele.", "模型完全在这台 Mac 上运行：音频和文本不会被发送出去。", "モデルはこの Mac 上だけで動作し、音声やテキストが外部に送られることはありません。",
        ]),
        "language.detail": row([
            "Auto-detect picks the language of each phrase. Pick one if short phrases come out in the wrong language.", "Автоопределение выбирает язык для каждой фразы. Укажите язык, если короткие фразы распознаются не на том языке.", "Die automatische Erkennung wählt die Sprache je Satz. Wählen Sie eine feste Sprache, wenn kurze Sätze falsch erkannt werden.", "La detección automática elige el idioma de cada frase. Elige uno si las frases cortas salen en otro idioma.", "La détection automatique choisit la langue de chaque phrase. Fixez-la si les phrases courtes sortent dans la mauvaise langue.", "A detecção automática escolhe o idioma de cada frase. Fixe um se frases curtas saírem no idioma errado.", "自动检测会为每句话判断语言。如果短句常被识别成别的语言，请手动指定。", "自動検出はフレーズごとに言語を判定します。短いフレーズが別の言語になる場合は固定してください。",
        ]),
        "vocabulary.title": row([
            "Vocabulary", "Словарь", "Wortschatz", "Vocabulario", "Vocabulaire", "Vocabulário", "词汇表", "用語集",
        ]),
        "vocabulary.detail": row([
            "Names, brands and terms the model should spell your way, separated by commas.", "Имена, названия и термины, которые модель должна писать по-вашему, через запятую.", "Namen, Marken und Begriffe, die das Modell so schreiben soll wie Sie – durch Kommas getrennt.", "Nombres, marcas y términos que el modelo debe escribir a tu manera, separados por comas.", "Noms, marques et termes que le modèle doit écrire à votre façon, séparés par des virgules.", "Nomes, marcas e termos que o modelo deve escrever do seu jeito, separados por vírgulas.", "希望模型按你的写法输出的人名、品牌和术语，用逗号分隔。", "モデルに指定どおり表記してほしい名前・ブランド・用語をカンマ区切りで入力します。",
        ]),
        "vocabulary.placeholder": row([
            "e.g. Vaulto, Kubernetes, TelePetr", "например: Vaulto, Kubernetes, TelePetr", "z. B. Vaulto, Kubernetes, TelePetr", "p. ej.: Vaulto, Kubernetes, TelePetr", "ex. : Vaulto, Kubernetes, TelePetr", "ex.: Vaulto, Kubernetes, TelePetr", "例如：Vaulto, Kubernetes, TelePetr", "例：Vaulto, Kubernetes, TelePetr",
        ]),
        "output.auto_paste": row([
            "Paste automatically", "Вставлять автоматически", "Automatisch einfügen", "Pegar automáticamente", "Coller automatiquement", "Colar automaticamente", "自动粘贴", "自動で貼り付け",
        ]),
        "output.auto_paste_detail": row([
            "Types the text where the cursor is. When off, the text is only copied to the clipboard.", "Текст появляется там, где стоит курсор. Если выключено, текст только копируется в буфер обмена.", "Fügt den Text an der Cursorposition ein. Wenn aus, wird er nur in die Zwischenablage kopiert.", "Escribe el texto donde está el cursor. Si está desactivado, solo se copia al portapapeles.", "Insère le texte à l'emplacement du curseur. Désactivé, il est seulement copié dans le presse-papiers.", "Insere o texto onde está o cursor. Desativado, ele só é copiado para a área de transferência.", "在光标处输入文本。关闭后仅复制到剪贴板。", "カーソル位置にテキストを入力します。オフの場合はクリップボードにコピーするだけです。",
        ]),
        "output.restore_clipboard": row([
            "Keep my clipboard", "Сохранять буфер обмена", "Zwischenablage behalten", "Conservar mi portapapeles", "Conserver mon presse-papiers", "Manter minha área de transferência", "保留剪贴板内容", "クリップボードを保持",
        ]),
        "output.restore_clipboard_detail": row([
            "Puts back what you had copied before the dictation", "Возвращает в буфер то, что вы скопировали до диктовки", "Stellt wieder her, was Sie vor dem Diktat kopiert hatten", "Restaura lo que habías copiado antes del dictado", "Remet ce que vous aviez copié avant la dictée", "Restaura o que você havia copiado antes do ditado", "恢复听写前你复制的内容", "音声入力前にコピーしていた内容を元に戻します",
        ]),
        "output.trailing_space_detail": row([
            "So several dictations in a row don't stick together", "Чтобы несколько диктовок подряд не слипались", "Damit mehrere Diktate hintereinander nicht zusammenkleben", "Para que varios dictados seguidos no se peguen", "Pour que plusieurs dictées d'affilée ne se collent pas", "Para que vários ditados seguidos não fiquem colados", "避免连续听写的内容粘在一起", "連続した音声入力がくっつかないように",
        ]),
        "output.sounds": row([
            "Sounds", "Звуки", "Töne", "Sonidos", "Sons", "Sons", "提示音", "サウンド",
        ]),
        "output.sounds_detail": row([
            "A soft sound when recording starts and stops", "Тихий звук в начале и в конце записи", "Ein leiser Ton bei Start und Ende der Aufnahme", "Un sonido suave al empezar y terminar la grabación", "Un son discret au début et à la fin de l'enregistrement", "Um som suave ao iniciar e parar a gravação", "录音开始和结束时播放轻柔提示音", "録音の開始時と終了時に小さな音を鳴らします",
        ]),
        "history.search": row([
            "Search history", "Поиск по истории", "Verlauf durchsuchen", "Buscar en el historial", "Rechercher dans l'historique", "Pesquisar no histórico", "搜索历史记录", "履歴を検索",
        ]),
        "history.today": row([
            "Today", "Сегодня", "Heute", "Hoy", "Aujourd'hui", "Hoje", "今天", "今日",
        ]),
        "history.yesterday": row([
            "Yesterday", "Вчера", "Gestern", "Ayer", "Hier", "Ontem", "昨天", "昨日",
        ]),
        "history.delete": row([
            "Delete", "Удалить", "Löschen", "Eliminar", "Supprimer", "Excluir", "删除", "削除",
        ]),
        "history.copied": row([
            "Copied", "Скопировано", "Kopiert", "Copiado", "Copié", "Copiado", "已复制", "コピーしました",
        ]),
        "history.no_results": row([
            "Nothing found", "Ничего не найдено", "Nichts gefunden", "Sin resultados", "Aucun résultat", "Nada encontrado", "未找到结果", "見つかりませんでした",
        ]),
        "history.clear_confirm": row([
            "Delete all dictations? This can't be undone.", "Удалить все диктовки? Это нельзя отменить.", "Alle Diktate löschen? Das lässt sich nicht rückgängig machen.", "¿Eliminar todos los dictados? No se puede deshacer.", "Supprimer toutes les dictées ? Action irréversible.", "Excluir todos os ditados? Isso não pode ser desfeito.", "删除所有听写记录？此操作无法撤销。", "すべての音声入力を削除しますか？元に戻せません。",
        ]),
        "general.launch_at_login": row([
            "Open at login", "Запускать при входе", "Beim Anmelden öffnen", "Abrir al iniciar sesión", "Ouvrir à l'ouverture de session", "Abrir ao iniciar sessão", "登录时打开", "ログイン時に開く",
        ]),
        "general.launch_at_login_detail": row([
            "Dictation is ready as soon as you turn on the Mac", "Диктовка готова сразу после включения Mac", "Das Diktat ist bereit, sobald Sie den Mac einschalten", "El dictado está listo en cuanto enciendes el Mac", "La dictée est prête dès que vous allumez le Mac", "O ditado fica pronto assim que você liga o Mac", "开机后即可使用听写", "Mac を起動するとすぐに音声入力を使えます",
        ]),
        "general.dock_detail": row([
            "When off, Vaulto Note lives only in the menu bar", "Если выключить, Vaulto Note будет только в строке меню", "Wenn aus, erscheint Vaulto Note nur in der Menüleiste", "Si se desactiva, Vaulto Note solo estará en la barra de menús", "Désactivé, Vaulto Note n'apparaît que dans la barre des menus", "Desativado, o Vaulto Note fica só na barra de menus", "关闭后，Vaulto Note 只显示在菜单栏中", "オフにすると Vaulto Note はメニューバーにだけ表示されます",
        ]),
        "general.permissions": row([
            "Permissions", "Разрешения", "Berechtigungen", "Permisos", "Autorisations", "Permissões", "权限", "許可",
        ]),
        "general.granted": row([
            "Allowed", "Разрешено", "Erlaubt", "Permitido", "Autorisé", "Permitido", "已允许", "許可済み",
        ]),
        "general.models_folder": row([
            "Models folder", "Папка с моделями", "Modellordner", "Carpeta de modelos", "Dossier des modèles", "Pasta de modelos", "模型文件夹", "モデルフォルダ",
        ]),
        "general.show_in_finder": row([
            "Show in Finder", "Показать в Finder", "Im Finder zeigen", "Mostrar en Finder", "Afficher dans le Finder", "Mostrar no Finder", "在访达中显示", "Finder で表示",
        ]),
        "general.version": row([
            "Version", "Версия", "Version", "Versión", "Version", "Versão", "版本", "バージョン",
        ]),
        "hud.esc_cancel": row([
            "Esc — cancel", "Esc — отмена", "Esc – abbrechen", "Esc: cancelar", "Échap : annuler", "Esc: cancelar", "Esc 取消", "Esc でキャンセル",
        ]),
        "hud.copied": row([
            "Copied to clipboard", "Скопировано в буфер обмена", "In die Zwischenablage kopiert", "Copiado al portapapeles", "Copié dans le presse-papiers", "Copiado para a área de transferência", "已复制到剪贴板", "クリップボードにコピーしました",
        ]),
        "menu.settings": row([
            "Settings…", "Настройки…", "Einstellungen…", "Ajustes…", "Réglages…", "Ajustes…", "设置…", "設定…",
        ]),
        "mainmenu.undo": row([
            "Undo", "Отменить", "Widerrufen", "Deshacer", "Annuler", "Desfazer", "撤销", "取り消す",
        ]),
        "mainmenu.cut": row([
            "Cut", "Вырезать", "Ausschneiden", "Cortar", "Couper", "Recortar", "剪切", "カット",
        ]),
    ]
}
