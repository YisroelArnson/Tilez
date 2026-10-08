# Developing Tilez

How to build, test, and release Tilez. For what the app does, see the [guide](GUIDE.md).

## Build and run

Requires macOS 14 or later, Swift 5.9 or later, and Apple's Command Line Tools. Desktop movement uses the existing private macOS bridge and is available on supported macOS versions (currently gated at macOS 26.4+). Opening an app whose new windows inherit full screen needs that bridge to move the new windows back to the target desktop.

```bash
bash scripts/build.sh
open "dist.noindex/Tilez.app"
```

The app uses a black-and-white three-pane icon and monochrome interface accents. The approved icon artwork lives in `Resources/AppIcon.png`. To regenerate the macOS icon sizes and `.icns` bundle after replacing the artwork:

```bash
swift -module-cache-path .build/module-cache scripts/icon.swift Resources
bash scripts/build.sh
```

The built app takes its version from the latest `v*` tag (or `TILEZ_VERSION`), with bundle ID `com.yisroelarnson.tilez`. Grant it Accessibility access when the inline prompt appears. No Input Monitoring permission is needed for the grid shortcut.

Builds go to `dist.noindex/`, which Spotlight skips, so local builds don't appear next to the installed app. Only one copy should run at a time. The app in `dist.noindex/` and an installed copy use the same bundle identity and preferences.

## Verification

```bash
bash scripts/test.sh
bash scripts/test-grid-editor.sh --require-display
# Native AppKit window-creation check with a disposable profile submenu:
bash scripts/test-window-menu.sh
# Optional native keyboard fixture with in-memory preferences:
bash scripts/build-keyboard-fixture.sh
```

The core suite covers geometry, app/window matching, window creation, desktop membership, live layouts, and grid resizing, empty cells, repeated apps, exact-window swaps, persistence, and overflow. The editor checks exercise selection, exact-window swaps, keyboard copying into empty and occupied cells, text-field shortcut routing, size preview/confirmation/cancellation, app and saved-grid search, atomic repetition undo, saved-grid loading/deletion, and the edit lock during launch with isolated preferences.

The isolated keyboard fixture was also checked with native input: Shift–Arrow swaps, ⌘Shift–Arrow copies into empty cells and protects occupied cells, rapid type-to-search preserves the first character, ↑/↓ moves the result highlight, Return and Escape restore grid focus, G/arrows/Return resizes, and ⌘S/⌘O saves and searches reusable grids. The fixture uses in-memory preferences.

Native UI checks include invoking the menu and shortcut, positioning the overlay on a large display, typing in app search, selecting Finder with Return, dragging cells, undoing swaps, saving/loading/removing a test grid, and applying both four- and eight-window ChatGPT grids. Some apps enforce sizes that cannot fit dense grids; their constraints remain visible in the editor.

## Release a DMG

Commit and push, then run one command with the new version:

```bash
bash scripts/release.sh 2.1.0
```

It builds Tilez (version 2.1.0, build number = commit count), signs it and the embedded Sparkle updater with your Developer ID and the hardened runtime, packages `dist.noindex/Tilez.dmg` with an Applications shortcut, notarizes and staples it, signs it for Sparkle, writes `dist.noindex/appcast.xml`, tags `v2.1.0`, and publishes a GitHub release with both files. It stops first if there are uncommitted changes, the tag exists, or `main` isn't pushed.

People who installed the DMG get the update automatically: Sparkle checks `releases/latest/download/appcast.xml` daily (and when the grid opens, if the last check was over an hour ago). A found update appears as a **Tilez x.y.z is available · Update** pill at the bottom of the grid instead of interrupting with an alert, and **… → Check for Updates…** checks right away. With automatic updates on, Sparkle downloads the update first; the pill then reads **ready · Restart**, and the menu item becomes **Restart to Install Tilez x.y.z**. Builds from source have no feed and keep updating with `scripts/update.sh`. The site's Download button links to `releases/latest/download/Tilez.dmg`.

One-time setup:

1. **Developer ID certificate.** In Keychain Access, choose Certificate Assistant → Request a Certificate From a Certificate Authority, and save the request to disk. At [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/add), create a **Developer ID Application** certificate from that request (only the account holder can), download it, and double-click it to add it to your login keychain. `security find-identity -v -p codesigning` should then list it.
2. **Notarization credentials.** Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, then save it under the profile the script uses:

   ```bash
   xcrun notarytool store-credentials tilez-notary --apple-id you@example.com --team-id YOURTEAMID
   ```

3. **Sparkle update key.** `.build/sparkle-2.10.0/bin/generate_keys` stores the private key in your login keychain and prints the public key, which `scripts/build.sh` embeds as `SUPublicEDKey`. Back up the private key with `generate_keys -x tilez-sparkle-key` and keep the file somewhere safe; without it, installed copies can't verify future updates.

## Install from source on another Mac

### First-time setup

1. Install Apple's Command Line Tools, which include Swift and git:

   ```bash
   xcode-select --install
   ```

2. Clone the repo and run the update script. On a first run it builds the app, installs it into `/Applications`, and launches it:

   ```bash
   mkdir -p ~/Developer/tools && cd ~/Developer/tools
   git clone https://github.com/YisroelArnson/Tilez.git
   cd Tilez
   bash scripts/update.sh
   ```

3. When Tilez asks, allow Accessibility access in **System Settings → Privacy & Security → Accessibility**.

4. Optional: add Tilez in **System Settings → General → Login Items** so it starts with your Mac.

### Updating

After pushing changes from your main Mac, run this on the other Mac:

```bash
cd ~/Developer/tools/Tilez
bash scripts/update.sh
```

The script pulls the latest `main`, rebuilds, quits the running copy, replaces `/Applications/Tilez.app`, and relaunches it. Accessibility access carries over between updates because the app is signed against its bundle ID. The script stops without changing anything if that copy has uncommitted changes, so make edits on your main Mac and push them. To install somewhere other than `/Applications`, set `TILEZ_INSTALL_DIR`.

## Website

The website lives in `docs/index.html` and is served by GitHub Pages at https://yisroelarnson.github.io/Tilez/. It's one self-contained file; push to `main` to update it.

## Preserved original

Before the redesign, the complete original Window Quilt source and built app were archived to:

`backups/WindowQuilt-before-grid-2026-09-14.tar.gz`

The Git commit `d59a1f5` on `main` and `backup/pre-grid-2026-09-14` preserves Window Quilt version 1.7.1. The desktop grid redesign is merged into `main`. The archive includes the original app bundle and distribution zip; disposable Swift build caches are excluded. Old preferences and saved setups are left intact (under the former `com.local.windowquilt` bundle ID), while saved templates remain under `savedGridsV2`. Legacy `desktopGridsV2` drafts are left intact but no longer override the live desktop.
