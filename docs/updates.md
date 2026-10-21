# Automatic updates

Vaulto Note 0.1.1 and later embed Sparkle 2.10.0. The updater starts after the
welcome guide, checks daily while the app runs, and shows a new-version window.
The user chooses Update; Sparkle downloads, verifies, installs and relaunches the
app. There are no silent installations. Settings → General has a check button
and an automatic-check toggle. The app menu and menu bar also have a check button.

An installation restart waits for recording, transcription, model download and
model preparation to finish. Models, history and preferences live outside the
app bundle and survive updates. macOS can ask for authorization if the app's
installation directory is not writable by the current user.

Dictation is marked idle only after its result is saved and delivered. The
updater then waits one quiet second for clipboard restoration before a pending
restart; starting another dictation or preparing a model cancels that window.

**Migration:** 0.1.0 has no updater. Its users must install 0.1.1 from the DMG
once, replacing the old app in Applications. Subsequent updates use Sparkle.

## Trust and release key

The app trusts the public Ed25519 key in `Resources/Info.plist`. The matching
private key is stored in the developer's login Keychain under Sparkle account
`com.vaultonote.mac.sparkle`. It is never committed or embedded in the app.
The app requires a signed feed and verifies signed ZIPs before extraction.

Back up the private key securely using Sparkle's `generate_keys -x` tool and
the same account. Keep the exported file outside the repository. To release
from another Mac, restore that exact key with `generate_keys -f`. Do not generate
a replacement key: apps already installed would reject its updates. Key rotation
needs a migration release signed by the old key.

For a signing environment that cannot show Keychain prompts, the official tools
also accept a protected private-key file through `SPARKLE_ED_KEY_FILE`. Export
with `generate_keys --account com.vaultonote.mac.sparkle -x <file>` into a private
directory outside the repository, set file permissions to 600, and remove the
temporary export after packaging. Never print the file or upload it with release
artifacts. Packaging verifies the result against the app's embedded public key,
including when this file option is used.

Ed25519 update signing and Apple Developer ID signing are separate. Sparkle
accepts an update when its Ed25519 signature is valid, so moving from the local
development certificate to Developer ID keeps updates working. The new signer
does reset macOS privacy permissions once (microphone, Accessibility).

## Developer ID signing and notarization

Public releases are signed with a **Developer ID Application** certificate and
notarized by Apple, so the DMG and app open without Gatekeeper warnings. The
scripts pick the first Developer ID Application identity in the Keychain
automatically (`scripts/signing-identity.sh`); `SIGN_IDENTITY` overrides it.
Without one they fall back to the local "Vaulto Note Dev" certificate, which is
only for development, and `scripts/package-release.sh` refuses a full release.

One-time setup on the release Mac:

For a Russian walkthrough, see [Подпись и выпуск для macOS](macos-release-ru.md).

1. Create the certificate. Xcode → Settings → Accounts → select the team →
   Manage Certificates → **+** → **Developer ID Application**. Only the Account
   Holder can create it. Back up the certificate with its private key (Keychain
   Access → export as .p12) outside the repository.
2. Create an app-specific password at https://account.apple.com (Sign-In and
   Security → App-Specific Passwords).
3. Store notarization credentials in the Keychain:
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun notarytool store-credentials vaulto-notary --apple-id <Apple-ID> --team-id <Team-ID>`
   and enter the app-specific password when asked. The Team ID is in
   parentheses at the end of the certificate name. `NOTARY_PROFILE` selects a
   different profile name.

An existing App Store Connect API key can be used instead of an app-specific
password. For a team key, store the credentials with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun notarytool store-credentials vaulto-notary --key <path-to-AuthKey.p8> --key-id <Key-ID> --issuer <Issuer-ID>`.
The key needs access to notarization for the signing team. Its Key ID and
Issuer ID are shown in App Store Connect → Users and Access → Integrations.
Keep the `.p8` file outside the repository. Individual keys omit `--issuer`.

Run `scripts/package-release.sh --check` before packaging. It checks for a
usable Developer ID identity, authenticates with Apple's notary service and
checks the Sparkle public key (a private-key file is checked for presence;
its signatures are verified during packaging). The same checks run automatically
before a full release. An explicitly requested signing identity must be usable;
the build will fail rather than silently substituting an ad-hoc signature.

Packaging then signs the app with the hardened runtime, a secure timestamp and
`Resources/VaultoNote.entitlements` (microphone access), notarizes and staples
the app, creates the ZIP from the stapled app, then signs, notarizes and staples
the DMG (`scripts/notarize.sh`). Notarization must finish before the Sparkle ZIP
is signed; any later archive modification breaks its update signature. Rejected
submissions print Apple's log, including when `notarytool` returns a failure
exit code. Submission results and rejection logs are retained in
`build/notarization/`. Check a result with
`spctl --assess --type execute --verbose "build/Vaulto Note.app"`.

Submission IDs are saved before polling begins. Temporary failures while checking
Apple's status are retried against the same submission. Authentication errors
and rejected submissions stop the process; a short stapling failure is retried.
To recover an interrupted app notarization without rebuilding or uploading again,
run `scripts/package-release.sh --resume-app <submission-id>`. Keep the original
signed `build/Vaulto Note.app` intact. Recovery checks its signature, signer and
version; Apple's ticket must match it before packaging can continue.
For a standalone app or DMG, use
`scripts/notarize.sh <target.app-or-dmg> <submission-id>`.

Local builds signed with "Vaulto Note Dev" skip the hardened runtime on the app:
without a Team ID, runtime library validation would reject whisper.framework.

## Publish a release

For local review without access to the release signing key, use
`scripts/package-release.sh --archives-only`. This produces DMG/ZIP artifacts
and no update feed; it is insufficient for a published auto-update release.

1. Increase `VERSION` (both CFBundleVersion and CFBundleShortVersionString).
2. Add `docs/releases/<version>.html` with the user-visible release notes.
3. Run `swift test` with Xcode's `DEVELOPER_DIR`, then `scripts/package-release.sh`.
   It notarizes the app and DMG, which usually takes a few minutes. The signing tools are fetched from the official pinned Sparkle release and
   checksum-verified. Packaging refuses a missing or mismatched signing key.
4. Inspect `build/release/Vaulto-Note-<version>.dmg`, `.zip` and `appcast.xml`.
   Packaging verifies both signatures against the embedded public key. To repeat
   without accessing private keys, run:
   `swift scripts/verify-update.swift "build/Vaulto Note.app" build/release/appcast.xml build/release/Vaulto-Note-<version>.zip`.
5. Create a GitHub **draft** release tagged `v<version>` at the tested commit.
   Attach all three artifacts, then publish the draft only after all uploads
   complete. Mark it the latest stable release. Do not replace published archives
   without regenerating and republishing the signed feed.
6. Verify the public feed URL below returns XML, and its ZIP URL downloads the
   exact signed artifact. Check from an older test installation that Update
   downloads, installs and relaunches; verify the new version and existing data.

The permanent feed URL is:
`https://github.com/dirusanov/vaulto-note-mac/releases/latest/download/appcast.xml`.
Each feed points to a version-specific ZIP under `releases/download/v<version>/`.
Every future latest stable release must include `appcast.xml`. Prereleases and
drafts do not change this feed. The generated feed contains the newest full ZIP;
an older installation can update directly without intermediate releases.

Source and API documentation: https://sparkle-project.org/documentation/.
