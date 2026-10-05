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

On first launch macOS asks for **Microphone** and **Accessibility** (needed to see the
hotkey in other apps and to paste with ⌘V). If the default model is missing, the app
downloads it (~1.6 GB) into `~/Library/Application Support/VaultoNote/Models/`.

## Use

- Hold **right ⌥ Option** (configurable: right ⌘, Fn/🌐), speak, release.
- A press shorter than 0.35 s, or one combined with another key (⌥+letter), is ignored.
- Menu bar icon → history (click to copy), language (auto-detect by default), model, key.

## Models

| Model | Size | Notes |
|---|---|---|
| Large v3 Turbo | 1.6 GB | default; ~0.6 s for an 8 s phrase on M5 Pro |
| Large v3 Turbo q5 | 574 MB | same model as the mobile app's "Turbo" |
| Large v3 | 3.1 GB | slightly more accurate, slower |

## Headless check

```bash
"build/Vaulto Note.app/Contents/MacOS/VaultoNote" --transcribe speech.wav [ru|en|auto]
```

Prints the transcript and `[lang] load=… audio=… transcribe=…` timings to stderr.

## Layout

- `WhisperEngine` — whisper.cpp wrapper, serialized on one queue
- `AudioRecorder` — AVAudioEngine → 16 kHz mono Float32
- `HotkeyMonitor` — hold-to-talk on a modifier key (`flagsChanged`)
- `TextInserter` — clipboard + synthetic ⌘V, restores the previous clipboard
- `TextCleanup` — port of the mobile app's Whisper hallucination filter
- `HUD`, `AppDelegate` — floating indicator and the menu bar UI

Next steps: notes window with audio, then Vaulto account + E2EE sync (must stay
byte-compatible with `vaulto_note_mobile/src/crypto/e2ee.ts`).
