# Window Quilt

A native macOS utility for quickly opening and editing a grid of app windows on the screen and desktop you are using.

Press **Control–Option–Space** or click the grid icon in the menu bar. One floating bar and a live grid replace the old setup and settings screens.

- Drag across the little grid in the bar to choose up to **6 columns × 4 rows**.
- Click a cell, search for an installed app, and select it. Mix apps or choose the same app more than once.
- **Drag a cell onto another to swap** their apps and existing window assignments. **Shift-drag to repeat an app**, creating a separate window when the grid opens. Right-click a cell to repeat its app into every empty cell.
- **Open grid / Return** opens missing windows and arranges them. Empty cells keep their space. Existing unrelated windows remain open.
- Invoke the same shortcut again to edit the current desktop's grid, then choose **Apply grid**.
- **⌘K** adds an app to the next empty cell, growing the grid if necessary. **1–9** chooses a cell, arrow keys select, Space edits, and Delete clears the selected cell.
- **⌘Z** undoes a grid edit. The bar's **…** menu also includes Undo last window arrangement, New empty grid, Close, and Quit.
- **Save** names an optional reusable grid. The bookmark button loads saved grids on any desktop. Saved grids contain app choices, not a fixed screen or desktop destination.
- **Escape** closes the app picker first, then the overlay. While opening windows it stops the request; windows already created stay available.

## Build and run

Requires macOS 14 or later, Swift 5.9 or later, and Apple's Command Line Tools. Desktop movement uses the existing private macOS bridge and is available on supported macOS versions (currently gated at macOS 26.4+). Opening an app whose new windows inherit full screen needs that bridge to move the new windows back to the target desktop.

```bash
bash scripts/build.sh
open "dist/Window Quilt.app"
```

The built app is version **2.0.0**, bundle ID `com.local.windowquilt`. Grant it Accessibility access when the inline prompt appears. No Input Monitoring permission is needed for the grid shortcut.

Only one copy should run at a time. The app in `dist/` and an installed copy use the same bundle identity and preferences.

## Window behavior

The invocation captures a particular display and desktop. Quilt reuses eligible windows there and opens independent windows for remaining cells. New windows can inherit an app's full-screen Space; Quilt identifies those new windows, waits for their transitions, restores them, and moves them back before applying the grid. Existing windows on unrelated desktops are not gathered. A window's identity includes its owning process launch, preventing stale IDs from matching after an app restart.

Each desktop remembers its latest draft and live assignments. Resizing removes cells from the grid but never closes their windows. The new interface does not run legacy saved-layout auto-restore or snapping monitors in the background.

Apps must support independent windows to occupy multiple cells. Quilt uses their enabled New Window command, not New Chat or New Conversation actions that might replace existing content. If an app cannot create a window, is showing a dialog, or imposes a minimum size, the overlay reports the problem. AX bounds are checked after the app has time to settle, with one retry before reporting a size constraint.

## Verification

```bash
bash scripts/test.sh
bash scripts/test-grid-editor.sh
```

The core suite covers geometry, app/window matching, window creation, desktop membership, live layouts, and grid resizing, empty cells, repeated apps, exact-window swaps, persistence, and overflow. The editor checks exercise real selection, swapping, repetition, undo, saved-grid loading/deletion, and the edit lock during launch with isolated preferences.

Native UI checks include invoking the menu and shortcut, positioning the overlay on a large display, typing in app search, selecting Finder with Return, dragging cells, undoing swaps, saving/loading/removing a test grid, and applying both four- and eight-window ChatGPT grids. Some apps enforce sizes that cannot fit dense grids; their constraints remain visible in the editor.

## Preserved original

Before the redesign, the complete original source and built app were archived to:

`backups/WindowQuilt-before-grid-2026-09-14.tar.gz`

The Git commit `d59a1f5` on `main` and `backup/pre-grid-2026-09-14` preserves version 1.7.1. The new work is on `feature/desktop-grid`. The archive includes the original app bundle and distribution zip; disposable Swift build caches are excluded. Old preferences and saved setups are left intact, while the new interface stores its data under `desktopGridsV2` and `savedGridsV2`.

Historical `*_UX_*.md`, `UI_POLISH*.md`, `ACTIVE_LAYOUTS.md`, `SIMPLIFIED_UI.md`, and `POPOVER_FIX.md` describe the preserved 1.x interface, not the new entry point.
