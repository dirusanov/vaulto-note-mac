# Vaulto Note for Mac

Menu bar dictation: hold a key, speak, release — the text is transcribed **locally**
with Whisper (whisper.cpp on Metal) and pasted into whatever app has focus.
Nothing leaves the Mac.

## Build

```bash
scripts/create-dev-cert.sh        # once: stable signing identity, keeps privacy permissions across rebuilds
scripts/build-app.sh --install    # builds build/Vaulto Note.app and copies it to ~/Applications
```

Needs Xcode (used via `DEVELOPER_DIR`, no `xcode-select` change). `build-app.sh`
downloads the prebuilt whisper.cpp XCFramework into `Vendor/` on first run
(`scripts/fetch-whisper.sh`, tag `b5130`).

First launch opens a five-step welcome (intro → microphone → Accessibility → shortcut →
practice dictation); each permission is requested only when the user clicks, and the step
advances by itself once it is granted. macOS asks for **Microphone** and **Accessibility** (needed to see the
hotkey in other apps and to paste with ⌘V). If the default model is missing, the app
downloads it (~1.6 GB) into `~/Library/Application Support/VaultoNote/Models/`.

## Use

- Hold **right ⌥ Option**, speak, release. Any single right-hand modifier, Fn, or a combo
  such as ⌃⌥Space can be recorded on the Shortcuts page.
- Modes: hold or tap (tap = hands-free, tap again to finish), hold only, press to start/stop.
  Esc cancels. ⌥+letter while holding is treated as typing, not dictation.
- Window pages: Overview, History (search, per-day groups), Shortcuts, Transcription (models,
  speech language, vocabulary), General (text insertion, interface language, login item).
- If no text field has focus, the text stays on the clipboard instead of being lost;
  ⌃⌘V pastes the last dictation again.

## Models

| Model | Size | Notes |
|---|---|---|
| Large v3 Turbo | 1.6 GB | default; ~0.6 s for an 8 s phrase on M5 Pro |
| Large v3 Turbo q5 | 574 MB | same model as the mobile app's "Turbo" |
| Large v3 | 3.1 GB | slightly more accurate, slower |

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Hotkey modes, text cleanup, shortcut storage, translation completeness, and end-to-end
transcription on the real model (skipped if it isn't downloaded).

## Icon

`swift scripts/make-icon.swift Resources/icon-glyph.png Resources/AppIcon-1024.png` puts the
mobile app's glyph on Apple's icon grid; a full-bleed square gets a grey placeholder on macOS.

## Headless check

```bash
"build/Vaulto Note.app/Contents/MacOS/VaultoNote" --transcribe speech.wav [ru|en|auto]
```

Prints the transcript and `[lang] load=… audio=… transcribe=…` timings to stderr.

## Reviewing the UI

```bash
"build/Vaulto Note.app/Contents/MacOS/VaultoNote" --snapshot /tmp/snap ru en de
```

Renders every page in light and dark with sample data to PNG — the quickest way to check
wrapping and alignment in long languages (German) after a layout change.

## Layout

- `WhisperEngine` — whisper.cpp wrapper, serialized on one queue
- `AudioRecorder` — AVAudioEngine → 16 kHz mono Float32
- `AppController` — app state and the dictation pipeline; the window binds to it
- `Hotkeys` — shortcut model, trigger modes, `flagsChanged` + Carbon hot keys
- `MainWindow`, `Components`, `Theme` — SwiftUI window in the mobile app's palette
- `Localization` — interface strings (en, ru, de, es, fr, pt, zh, ja)
- `TextInserter` — clipboard + synthetic ⌘V, restores the previous clipboard
- `TextCleanup` — port of the mobile app's Whisper hallucination filter
- `HUD`, `AppDelegate` — floating recording indicator, status bar menu, main menu

Next steps: notes window with audio, then Vaulto account + E2EE sync (must stay
byte-compatible with `vaulto_note_mobile/src/crypto/e2ee.ts`).
