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

Ed25519 update signing and Apple Developer ID signing are separate. This repo's
local development certificate does not provide Gatekeeper trust or notarization.
For frictionless first installation, releases still need Developer ID signing
and Apple notarization. When adding notarization, complete it and staple the app
before packaging/signing the Sparkle ZIP; any later archive modification breaks
its update signature.

## Publish a release

For local review without access to the release signing key, use
`scripts/package-release.sh --archives-only`. This produces DMG/ZIP artifacts
and no update feed; it is insufficient for a published auto-update release.

1. Increase `VERSION` (both CFBundleVersion and CFBundleShortVersionString).
2. Add `docs/releases/<version>.html` with the user-visible release notes.
3. Run `swift test` with Xcode's `DEVELOPER_DIR`, then `scripts/package-release.sh`.
   The signing tools are fetched from the official pinned Sparkle release and
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
