# Подпись и выпуск Vaulto Note для macOS

Цель: пользователь скачивает DMG с GitHub или сайта, перетаскивает Vaulto Note
в «Программы» и запускает приложение. Для этого приложение и DMG подписываются
сертификатом **Developer ID Application**, проходят нотариализацию Apple,
а полученные билеты прикрепляются к файлам (stapling).

Текущая сборка рассчитана на Apple Silicon (M1 и новее), macOS 14+.

## Однократная настройка на Mac разработчика

1. В Xcode открой **Settings → Accounts**, добавь Apple Account и выбери команду
   с активной подпиской Apple Developer Program.
2. Открой **Manage Certificates → + → Developer ID Application**.
   Если сертификат уже существует на другом Mac, перенеси его вместе с закрытым
   ключом через защищённый экспорт `.p12` в Связке ключей.
3. В обычном Терминале выполни `security find-identity -v -p codesigning`.
   В списке должна быть строка `Developer ID Application: … (TEAMID)`.
   Одного Apple Development или Apple Distribution для этого выпуска недостаточно.
4. На [account.apple.com](https://account.apple.com) создай пароль приложения:
   **Sign-In and Security → App-Specific Passwords**.
5. Сохрани учётные данные нотариализации в Связке ключей:

   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcrun notarytool store-credentials vaulto-notary \
       --apple-id 'ТВОЙ_APPLE_ID' --team-id 'ТВОЙ_TEAM_ID'
   ```

   Введи пароль приложения в защищённом приглашении Терминала.
   Team ID указан в аккаунте разработчика и в скобках у сертификата.
   Пароль и закрытые ключи остаются на твоём Mac; в чат и репозиторий они не нужны.

Если уже есть подходящий ключ App Store Connect API, вместо шагов 4–5 можно
сохранить его в профиль нотариализации:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun notarytool store-credentials vaulto-notary \
    --key '/путь/вне/репозитория/AuthKey_KEYID.p8' \
    --key-id 'KEYID' --issuer 'ISSUER_ID'
```

Key ID и Issuer ID командного ключа показаны в App Store Connect → Users and
Access → Integrations. У ключа должен быть доступ к нотариализации для команды,
выдавшей сертификат. Для индивидуального ключа `--issuer` не указывается.

## Проверка и сборка

Из папки `vaulto-note-mac`:

```bash
scripts/package-release.sh --check
scripts/package-release.sh
```

Первая команда проверяет доступность сертификата с закрытым ключом,
авторизацию в Apple и ключ автообновлений Sparkle. Вторая собирает приложение,
подписывает вложенные компоненты и само приложение, отправляет его в Apple,
прикрепляет билет, создаёт ZIP и DMG, затем подписывает и нотариализирует DMG.
После этого создаётся и проверяется подписанная лента автообновлений.

Существующий ключ Sparkle из Связки ключей надо сохранить: он соответствует
публичному ключу, уже встроенному в приложение. Подробнее: [updates.md](updates.md).
При нескольких сертификатах можно выбрать нужный через
`SIGN_IDENTITY='Developer ID Application: Имя (TEAMID)'`.

Результат находится в `build/release/`:

- `Vaulto-Note-<версия>.dmg` — установка перетаскиванием в «Программы»;
- `Vaulto-Note-<версия>.zip` — архив для автообновлений;
- `appcast.xml` — подписанная лента Sparkle.

Результаты отправок в Apple сохраняются в `build/notarization/`.
Успешное создание локальных архивов с `--archives-only` само по себе
не подтверждает готовность публичного релиза.

## Публикация и проверка установки

Загрузи все три файла в GitHub Release `v<версия>`. До публикации проверь
артефакты и исходный commit в черновике. После публикации на сайте можно
сослаться на DMG этого релиза. Приложение обновляется по постоянному адресу
`https://github.com/dirusanov/vaulto-note-mac/releases/latest/download/appcast.xml`.

Проверка готового результата:

```bash
codesign --verify --deep --strict 'build/Vaulto Note.app'
spctl --assess --type execute --verbose 'build/Vaulto Note.app'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun stapler validate 'build/Vaulto Note.app'
```

Отдельно скачай опубликованный DMG через браузер, открой его, перенеси
приложение в «Программы» и запусти обычным двойным нажатием. Это проверит
реальный путь установки с атрибутом quarantine. Ожидается обычное подтверждение
первого запуска скачанного приложения; обход Gatekeeper не требуется.
Далее приложение запросит микрофон и «Универсальный доступ» для диктовки.

Официальные инструкции Apple:
[Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates),
[нотариализация](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
