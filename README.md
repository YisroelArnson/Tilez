# Tilez

*Formerly Window Quilt.*

A native macOS pane editor for the screen and desktop you are using. The overlay starts from the windows that are actually visible, including uneven sizes and overlapping arrangements. An empty desktop starts with one empty pane.

Press **Control–Option–Space** or click the grid icon in the menu bar. The preview mirrors the current desktop. Opening it does not move, restore, or open any windows.

- Use a **+ on any pane edge** to split off a neighbor, then choose its app. **Drag any edge of a pane** to resize it, or **drag a corner** to resize in both directions. An edge shared with other panes moves them along with it, like dragging the divider between them; an edge at the screen border or facing empty space moves on its own and stops just short of the next pane. Dragging a corner where panes meet moves that whole junction. **Double-click** a divider to center it between its panes again. Next to each edge's **+**, a merge button grows that pane over its neighbors on that side when they line up, such as turning a column of stacked panes into one tall pane. The pane whose button you click keeps its app. Drag panes to swap them.
- Drag across the little grid in the bar to explicitly redistribute the current panes into up to **6 columns × 4 rows**.
- Click a pane to select it. **Double-click** it, or click its app icon, to search for an installed app and select it. Hovering a pane shows its edge controls, so you can split or merge without selecting it first. Mix apps or choose the same app more than once.
- **Drag a cell onto another to swap** their apps and existing window assignments. While you drag, the other pane slides into your pane's spot so you can see the result; move back to cancel. **Shift-drag to copy an app** into another pane, creating a separate window when the grid opens. Right-click a cell to repeat its app into every empty cell.
- **Apply / Return** commits the preview. New panes open independent windows on the desktop where you invoked Tilez. Existing windows on other desktops are not borrowed.
- **Remove pane / Delete** expands a neighboring pane where possible and closes the removed window on Apply. Undo restores the pane before applying; Escape cancels the draft. Native save dialogs remain under the app’s control.
- **⌘Shift–Delete** removes all panes from the current draft, leaving one empty cell. Press **Return / Apply** to close their windows, or **⌘Z** to restore the entire layout in one step. Also available under **… → Close all panes on Apply**.
- Invoke the same shortcut again to edit the current desktop's grid, then choose **Apply**.
- The keyboard shortcut targets the active app’s foremost window’s display; clicking the menu icon targets that menu bar’s display. Each desktop remembers the selected cell during the session.
- **Arrow keys** select neighboring cells without wrapping. **Shift–Arrow** moves or swaps the selected app and its exact window assignment. **⌘Shift–Arrow** copies the app into the neighboring cell and follows the copy. Copying onto a different app replaces it, and that pane's window closes on Apply; copying onto the same app just moves the selection, keeping its window. These edit the draft; **Return** applies it to your windows.
- **Option–Arrow** splits the selected pane toward that arrow (left, right, above, or below) and opens the app chooser for the new pane. Type an app name and press Return to assign it. **⌘Z** undoes the split after dismissing the chooser.
- **Type an app name** to search for the selected cell. **↑/↓** highlights a result; **Return** assigns it; **Escape** goes back. **1–9** opens a cell’s picker, **Space** opens the selected cell’s picker, and **Delete** removes its pane. To start a search with the reserved **G** key or a cell number, press Space first.
- **Option–Shift–Arrow** merges the selected pane with the pane or panes beside it in that direction, when they line up into one rectangle. The selected pane keeps its app; absorbed windows close on Apply, and **⌘Z** undoes the merge.
- **⌘R** realigns panes that have drifted out of line, such as windows captured from the desktop. Edges within a few percent of each other snap onto one shared line with an even gap, panes near the screen edge reach it, and near-even splits settle on halves, thirds, or quarters. The arrangement stays the same, larger holes are kept, and **⌘Z** undoes it. Also available under **… → Realign panes**.
- **G** turns the toolbar's layout preview into a size picker. Hover or use **←/→** (columns) and **↑/↓** (rows), then click or press **Return** to confirm. **Escape** or **G** again cancels.
- **⌘K** uses an empty pane or splits the selected pane to make room. **⌘C / ⌘V** copies an app assignment into an empty cell, without sharing its live window binding.
- **⌘Z** undoes a grid edit. The bar's **…** menu also includes Undo last window arrangement, New empty grid, Close, and Quit.
- **Save / ⌘S** names an optional reusable grid. **⌘O** or the chevron beside Save opens searchable saved grids: type, use ↑/↓, then Return to load a draft on any desktop. Saved grids contain app choices, not a fixed screen or desktop destination.
- **Escape** closes the app picker first, then the overlay. While opening windows it stops the request; windows already created stay available.

### Quick add a tile

Press **Control–Option–N** anywhere to open a search panel of your apps, with recently added apps at the top. Type to filter, use ↑/↓ to choose, and press Return (or click) to open the app as a new tile. Tilez fills an empty pane if the desktop has one; otherwise it splits the largest pane along its longer side and fits the new window there. Every other window stays where it is. Escape, or clicking elsewhere, closes the panel.

### Realign windows

Press **Control–Option–R** anywhere to tidy the windows on the current screen and desktop without opening the grid. It works like **⌘R** in the grid: edges that nearly line up snap onto shared lines with an even gap, windows near the screen edge reach it, and near-even splits settle on halves, thirds, or quarters. Windows glide into place and keep their arrangement; wider holes, minimized, hidden, and full-screen windows are left alone. An enlarged window on that screen returns to its pane first. **… → Undo last window arrangement** puts everything back. With the grid open, the shortcut realigns its panes instead.

### Swap two windows by dragging

Hold **Control–Option** and drag a window from anywhere inside it. The window follows the pointer; move it over another window and the two trade places live, gliding into position: the other window slides into your window's original spot and yours takes on its size. Release there to keep the swap. Release anywhere else, even after a small nudge, and the window returns exactly to where it started. A Control–Option click without dragging enlarges the window instead, and ordinary title-bar drags move windows as usual. Enlarged and full-screen windows never swap.

### Enlarge a window temporarily

Press **Control–Option–Return** in any window, or **Control–Option–click** it, to enlarge it over its neighbors, filling the screen with a 10-point margin. Nothing else moves. It stays enlarged while you click or switch to other windows. Each screen and desktop keeps its own enlarged window, so you can enlarge one window per monitor and per desktop without them affecting each other. Press the shortcut again on the same screen and desktop, or Control–Option–click the enlarged window, to return it to exactly where it was. Control–Option–clicking a different window puts back the one enlarged on that screen and desktop and enlarges the clicked one. Tilez consumes Control–Option–clicks so apps don't also treat them as right-clicks; ordinary clicks and Control-clicks are untouched. Opening the grid puts back only the enlarged window on the screen and desktop it opens on; quitting Tilez puts them all back. Only standard, resizable windows outside full screen can be enlarged; anything else beeps.

The website lives in `docs/index.html` and is served by GitHub Pages at https://yisroelarnson.github.io/Tilez/. It's one self-contained file; push to `main` to update it.

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

The built app is version **2.0.0**, bundle ID `com.yisroelarnson.tilez`. Grant it Accessibility access when the inline prompt appears. No Input Monitoring permission is needed for the grid shortcut.

Builds go to `dist.noindex/`, which Spotlight skips, so local builds don't appear next to the installed app. Only one copy should run at a time. The app in `dist.noindex/` and an installed copy use the same bundle identity and preferences.

## Release a DMG

Commit and push, then run one command with the new version:

```bash
bash scripts/release.sh 2.1.0
```

It builds Tilez (version 2.1.0, build number = commit count), signs it and the embedded Sparkle updater with your Developer ID and the hardened runtime, packages `dist.noindex/Tilez.dmg` with an Applications shortcut, notarizes and staples it, signs it for Sparkle, writes `dist.noindex/appcast.xml`, tags `v2.1.0`, and publishes a GitHub release with both files. It stops first if there are uncommitted changes, the tag exists, or `main` isn't pushed.

People who installed the DMG get the update automatically: Sparkle checks `releases/latest/download/appcast.xml` daily (and when the grid opens, if the last check was over six hours ago). A found update appears as a **Tilez x.y.z is available · Update** pill at the bottom of the grid instead of interrupting with an alert, and **… → Check for Updates…** checks right away. Builds from source have no feed and keep updating with `scripts/update.sh`. The site's Download button links to `releases/latest/download/Tilez.dmg`.

One-time setup:

1. **Developer ID certificate.** In Keychain Access, choose Certificate Assistant → Request a Certificate From a Certificate Authority, and save the request to disk. At [developer.apple.com → Certificates](https://developer.apple.com/account/resources/certificates/add), create a **Developer ID Application** certificate from that request (only the account holder can), download it, and double-click it to add it to your login keychain. `security find-identity -v -p codesigning` should then list it.
2. **Notarization credentials.** Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords, then save it under the profile the script uses:

   ```bash
   xcrun notarytool store-credentials tilez-notary --apple-id you@example.com --team-id YOURTEAMID
   ```

3. **Sparkle update key.** `.build/sparkle-2.10.0/bin/generate_keys` stores the private key in your login keychain and prints the public key, which `scripts/build.sh` embeds as `SUPublicEDKey`. Back up the private key with `generate_keys -x tilez-sparkle-key` and keep the file somewhere safe; without it, installed copies can't verify future updates.

## Install on another Mac

### First-time setup

1. Install Apple's Command Line Tools, which include Swift and git:

   ```bash
   xcode-select --install
   ```

2. Install the GitHub CLI and sign in. The repo is private, so this Mac needs your GitHub account. If Homebrew isn't installed yet, get it from [brew.sh](https://brew.sh) first:

   ```bash
   brew install gh
   gh auth login
   ```

3. Clone the repo and run the update script. On a first run it builds the app, installs it into `/Applications`, and launches it:

   ```bash
   mkdir -p ~/Developer/tools && cd ~/Developer/tools
   gh repo clone YisroelArnson/Tilez
   cd Tilez
   bash scripts/update.sh
   ```

4. When Tilez asks, allow Accessibility access in **System Settings → Privacy & Security → Accessibility**.

5. Optional: turn on **Launch Tilez at login** in the app.

### Updating

After pushing changes from your main Mac, run this on the other Mac:

```bash
cd ~/Developer/tools/Tilez
bash scripts/update.sh
```

The script pulls the latest `main`, rebuilds, quits the running copy, replaces `/Applications/Tilez.app`, and relaunches it. Accessibility access carries over between updates because the app is signed against its bundle ID. The script stops without changing anything if that copy has uncommitted changes, so make edits on your main Mac and push them. To install somewhere other than `/Applications`, set `TILEZ_INSTALL_DIR`.

## Window behavior

The invocation captures a particular display and desktop. Tilez reuses eligible windows there and opens independent windows for remaining cells. New windows can inherit an app's full-screen Space; Tilez identifies those new windows, waits for their transitions, restores them, and moves them back before applying the grid. Existing windows on unrelated desktops are not gathered. A window's identity includes its owning process launch, preventing stale IDs from matching after an app restart.

Each invocation takes a fresh WindowServer snapshot of the visible desktop. Fully covered windows are omitted; partially visible windows retain their actual bounds. Accessibility refinement runs off the UI thread and never overwrites a draft once editing starts. Escape discards the draft. Only explicitly saved templates persist; they include unequal pane geometry but no live window identities. The editor does not run legacy all-app polling or auto-restore monitors.

A native macOS full-screen window appears as one pane. Applying it unchanged keeps it full screen. Applying edits first restores that exact window to its regular desktop on the same display, re-reads the usable display bounds, and opens any added panes there. The overlay explains this transition before Apply. Switching desktops while editing dismisses the overlay.

Apps must support independent windows to occupy multiple cells. Tilez uses their enabled New Window command, not New Chat or New Conversation actions that might replace existing content. If an app cannot create a window, is showing a dialog, or imposes a minimum size, the overlay reports the problem. AX bounds are checked after the app has time to settle, with bounded retries for only the windows that have not settled. Windows already in place finish immediately.

New Window submenus are resolved to an enabled action, preferring the default profile's Command-N item. This supports Terminal-style profile menus without pressing the submenu heading or choosing an arbitrary profile. Menu traversal remains bounded and runs on the Accessibility worker during grid application.

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

## Preserved original

Before the redesign, the complete original Window Quilt source and built app were archived to:

`backups/WindowQuilt-before-grid-2026-09-14.tar.gz`

The Git commit `d59a1f5` on `main` and `backup/pre-grid-2026-09-14` preserves Window Quilt version 1.7.1. The desktop grid redesign is merged into `main`. The archive includes the original app bundle and distribution zip; disposable Swift build caches are excluded. Old preferences and saved setups are left intact (under the former `com.local.windowquilt` bundle ID), while saved templates remain under `savedGridsV2`. Legacy `desktopGridsV2` drafts are left intact but no longer override the live desktop.

Historical `*_UX_*.md`, `UI_POLISH*.md`, `ACTIVE_LAYOUTS.md`, `SIMPLIFIED_UI.md`, and `POPOVER_FIX.md` describe the preserved 1.x interface, not the new entry point.
