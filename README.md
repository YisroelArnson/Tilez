# Tilez

*Formerly Window Quilt.*

A native macOS pane editor for the screen and desktop you are using. The overlay starts from the windows that are actually visible, including uneven sizes and overlapping arrangements. An empty desktop starts with one empty pane.

Press **Control–Option–Space** or click the grid icon in the menu bar. The preview mirrors the current desktop. Opening it does not move, restore, or open any windows.

- Use a **+ on any pane edge** to split off a neighbor, then choose its app. **Drag a divider** to resize adjacent panes, or **double-click** it to center it between them again. Next to each edge's **+**, a merge button grows that pane over its neighbors on that side when they line up, such as turning a column of stacked panes into one tall pane. The pane whose button you click keeps its app. Drag panes to swap them.
- Drag across the little grid in the bar to explicitly redistribute the current panes into up to **6 columns × 4 rows**.
- Click a pane to select it. **Double-click** it, or click its app icon, to search for an installed app and select it. Hovering a pane shows its edge controls, so you can split or merge without selecting it first. Mix apps or choose the same app more than once.
- **Drag a cell onto another to swap** their apps and existing window assignments. **Shift-drag to repeat an app**, creating a separate window when the grid opens. Right-click a cell to repeat its app into every empty cell.
- **Apply / Return** commits the preview. New panes open independent windows on the desktop where you invoked Tilez. Existing windows on other desktops are not borrowed.
- **Remove pane / Delete** expands a neighboring pane where possible and closes the removed window on Apply. Undo restores the pane before applying; Escape cancels the draft. Native save dialogs remain under the app’s control.
- **⌘Shift–Delete** removes all panes from the current draft, leaving one empty cell. Press **Return / Apply** to close their windows, or **⌘Z** to restore the entire layout in one step. Also available under **… → Close all panes on Apply**.
- Invoke the same shortcut again to edit the current desktop's grid, then choose **Apply**.
- The keyboard shortcut targets the active app’s foremost window’s display; clicking the menu icon targets that menu bar’s display. Each desktop remembers the selected cell during the session.
- **Arrow keys** select neighboring cells without wrapping. **Shift–Arrow** moves or swaps the selected app and its exact window assignment. **⌘Shift–Arrow** copies the app into the neighboring cell and follows the copy. Copying onto a different app replaces it, and that pane's window closes on Apply; copying onto the same app just moves the selection, keeping its window. These edit the draft; **Return** applies it to your windows.
- **Option–Arrow** splits the selected pane toward that arrow (left, right, above, or below) and opens the app chooser for the new pane. Type an app name and press Return to assign it. **⌘Z** undoes the split after dismissing the chooser.
- **Type an app name** to search for the selected cell. **↑/↓** highlights a result; **Return** assigns it; **Escape** goes back. **1–9** opens a cell’s picker, **Space** opens the selected cell’s picker, and **Delete** removes its pane. To start a search with the reserved **G** key or a cell number, press Space first.
- **Option–Shift–Arrow** merges the selected pane with the pane or panes beside it in that direction, when they line up into one rectangle. The selected pane keeps its app; absorbed windows close on Apply, and **⌘Z** undoes the merge.
- **G** turns the toolbar's layout preview into a size picker. Hover or use **←/→** (columns) and **↑/↓** (rows), then click or press **Return** to confirm. **Escape** or **G** again cancels.
- **⌘K** uses an empty pane or splits the selected pane to make room. **⌘C / ⌘V** copies an app assignment into an empty cell, without sharing its live window binding.
- **⌘Z** undoes a grid edit. The bar's **…** menu also includes Undo last window arrangement, New empty grid, Close, and Quit.
- **Save / ⌘S** names an optional reusable grid. **⌘O** or the bookmark button opens searchable saved grids: type, use ↑/↓, then Return to load a draft on any desktop. Saved grids contain app choices, not a fixed screen or desktop destination.
- **Escape** closes the app picker first, then the overlay. While opening windows it stops the request; windows already created stay available.

## Build and run

Requires macOS 14 or later, Swift 5.9 or later, and Apple's Command Line Tools. Desktop movement uses the existing private macOS bridge and is available on supported macOS versions (currently gated at macOS 26.4+). Opening an app whose new windows inherit full screen needs that bridge to move the new windows back to the target desktop.

```bash
bash scripts/build.sh
open "dist/Tilez.app"
```

The app uses a black-and-white three-pane icon and monochrome interface accents. The approved icon artwork lives in `Resources/AppIcon.png`. To regenerate the macOS icon sizes and `.icns` bundle after replacing the artwork:

```bash
swift -module-cache-path .build/module-cache scripts/icon.swift Resources
bash scripts/build.sh
```

The built app is version **2.0.0**, bundle ID `com.local.tilez`. Grant it Accessibility access when the inline prompt appears. No Input Monitoring permission is needed for the grid shortcut.

Only one copy should run at a time. The app in `dist/` and an installed copy use the same bundle identity and preferences.

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
