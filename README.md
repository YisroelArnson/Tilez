# Window Quilt

A standalone native macOS menu-bar window manager. Swift, AppKit, and SwiftUI; no external dependencies or network access. Requires macOS 14 or later. The local build targets this Mac's architecture (Apple silicon).

## Start

Open **Window Quilt.app** in `dist` (or the installed copy in `~/Applications`).

1. Click **Grant Access**.
2. In **System Settings → Privacy & Security → Accessibility**, enable **Window Quilt**. If it is not listed, click **+** and select the app. macOS may request your password or Touch ID.
3. Return to Quilt. Choose **New arrangement…** (the grid appears immediately if you have no saved setups), click or drag to select a grid, then choose an app. A 3 × 2 grid requests six windows. Quilt reuses eligible windows on the destination desktop and opens the missing ones.
4. Choose **Save this setup** to repeat it with one click from the main window or menu bar. Expand **Options** only when you want to change spacing, desktop, display, or window behavior. **Use as defaults** remembers your choices for future arrangements; existing setups retain their own options. Closing the main window leaves Quilt running; Quit is in the menu-bar gear menu.

Accessibility is required for window discovery, moving, and resizing. Optional title-bar gestures may also need **Input Monitoring**, available from Quilt's Settings. Restart Quilt if macOS requests it. No Screen Recording permission is needed.

## Window discovery and restoration (1.3)

- The window list includes minimized, hidden, full-screen and fixed-size document windows. WindowServer IDs and geometry keep windows on other macOS Spaces in the inventory even when an app's AXWindows list omits them. These appear as **Other desktop** until Quilt brings their Space into view; an unavailable title falls back to the app name.
- **Open app…** launches an installed app directly from Arrange.
- **Open & Tile** restores minimized windows, exits inherited full screen, waits for a stable frame and normal desktop membership, then moves and tiles the selected set. Full-screen toolbar objects are excluded from the count.
- Enable **Keep full-screen windows in full screen** to count those windows toward the total while leaving them in their own Spaces. Only the remaining windows are tiled. This choice is saved per setup; older setups still load.
- App launching/reopening is separate from creating extra windows. Quilt uses an actual enabled New Window menu command, including Finder's New Finder Window. It does not confuse New Conversation with a new native window. The installed Claude version and Activity Monitor do not expose a general New Window command: choose one window to show/restore their main window. Activity Monitor's explicit main-window menu command is supported. Requests for unsupported additional windows stop with an explanation.
- Watch mode leaves minimized, hidden, full-screen and other-desktop windows alone. Electron apps use the [documented accessibility handshake](https://www.electronjs.org/docs/latest/tutorial/accessibility).

## Reusable setups and separate desktops (1.2)

In **New arrangement…**, select the grid and then the app. After running it, choose **Save this setup**. Saved setup cards run with one click; their **…** menu contains Edit, Duplicate, and Delete. Options starts collapsed and includes custom counts up to 40. The searchable app list includes installed apps and launches them if needed. **Choose another installed app…** supports apps stored elsewhere.

- **Current desktop** reuses eligible windows on that desktop, opening any missing ones.
- **New desktop each time** creates a normal macOS Space and opens a fresh set there.
- A **named desktop entry** targets that existing Space. Its identity is saved, so rearranging desktop order does not silently redirect a setup. If it is removed, Quilt asks you to edit the setup.
- **Open a fresh set of windows** creates a separate set even when using an existing desktop.
- Use your normal macOS three- or four-finger swipe to switch between desktops.
- **Desktop snapshots** remain available in their own tab; they capture the open-app positions. A saved setup is an explicit recipe for one app.
- The Arrange page also has desktop/fresh-window controls and **Save Setup** for its current configuration.
- Desktop grouping keeps manual tiling grids separate for windows assigned to distinct Spaces.

Quilt verifies each window's actual desktop membership before tiling and confirms desktop switches. It stops with an error if macOS cannot complete the operation. Cancelled/failed operations may leave newly opened windows or an empty new desktop; existing windows are not closed. Existing apps can briefly become active during window creation.

**Compatibility:** Desktop enumeration and moves use dynamically loaded, undocumented SkyLight interfaces; creating/selecting desktops uses Mission Control Accessibility. Cross-desktop moves require macOS 26.4+ and were tested on 26.6.2. Apple may change these interfaces. No SIP changes, Dock injection, extra daemon, or Screen Recording permission is used. Mission Control may appear briefly. Normal window tiling still requires macOS 14+.

API references used to establish compatibility: [Hammerspoon Spaces](https://github.com/Hammerspoon/hammerspoon/tree/master/extensions/spaces), [DockDoor's desktop bridge](https://github.com/ejbills/DockDoor/blob/main/DockDoor/Utilities/PrivateApis.swift), and [Apple's Spaces guide](https://support.apple.com/en-gb/guide/mac-help/mh14112/mac).

## Features

- Choose 1–40 windows and use **Open & Tile** to create missing windows before arranging them. The count is remembered between launches.
- Existing windows are reused; selecting fewer tiles a subset and leaves extras open. Window checkboxes prioritize which existing windows are reused.
- Creation uses the app's enabled **New Window** menu command. Apps must already be running, but may start with zero eligible windows.
- Live creation progress and cancellation from the Arrange page or menu bar. Quilt waits for each new window and stops after a 10-second per-window timeout; it never blindly repeats a failed request.
- App-wide grid tiling from the menu bar.
- Window checkboxes for arranging a selected subset.
- Automatic grids or custom rows/columns (0 means auto); rows expand to accommodate the selected windows.
- Adjustable outer margins and gaps, from 0 to 32 points.
- Keep windows on their current displays or gather them onto a chosen display.
- Per-app Watch mode, responding to eligible windows opening, closing, minimizing, or returning. Watch resets when the watched app or Quilt exits.
- Global shortcuts for halves, thirds, two-thirds, quarters, maximize, and center. Repeated arrows within two seconds cycle ½ → ⅓ → ⅔.
- Shortcut recording, duplicate detection, registration conflict reporting, disabling, and default reset.
- Drag-to-edge snapping with a translucent destination preview.
- Optional two-finger trackpad title-bar swipes: left/right halves, up maximize, down center.
- Draw-to-place overlay with a 24 × 16 guide and Escape cancellation.
- Move to the next/previous display while preserving relative position and size.
- Named desktop layouts, editable names, one-click restoration, and automatic restoration when a saved display setup returns.
- Undo for up to 50 arrangements or observed manual moves.
- Optional launch at login, settings, and a built-in guide.
- Preferences and saved layouts stay in the local `com.local.windowquilt` UserDefaults domain. Undo and Watch state stay in memory.

## Default shortcuts

Every shortcut starts with **Control + Option**.

| Key | Action |
| --- | --- |
| T | Tile the focused app |
| ← / → / ↑ / ↓ | Snap and cycle half, third, two-thirds |
| U / I / J / K | Top-left / top-right / bottom-left / bottom-right |
| D / F / G | First / middle / last third |
| Return | Maximize |
| C | Center |
| Space | Draw to place |
| [ / ] | Previous / next display |
| Z | Undo |

## Build and check

Apple Command Line Tools are sufficient; a full Xcode installation is not required.

```sh
./scripts/build.sh
./scripts/test.sh
open "dist/Window Quilt.app"
```

The build creates an ad-hoc signed local app. It is not notarized for public distribution. The stable bundle identity is `com.local.windowquilt`. If permissions stop working after rebuilding or moving the app, remove its old Accessibility entry and add the current app.

The check runner uses plain Swift so it works with Command Line Tools installations that do not include XCTest. It checks portrait/landscape grids for 1–40 windows, negative display coordinates, gap limits, custom grid expansion, snapping, normalized layout conversion, and saved-window matching. It fails the process on any failed assertion.

The icon is generated with AppKit vector drawing, independently of the interface and branding of other window managers. To regenerate it:

```sh
swift -module-cache-path .build/module-cache scripts/icon.swift Resources
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

## Practical limits

- App-enforced minimum window sizes take precedence. A dense grid can overlap if the app refuses smaller dimensions; the status message reports constrained windows.
- The inventory includes document windows in all supported states and Spaces. Dialogs and transient full-screen toolbars are excluded when identifiable; unexposed windows use WindowServer metadata and may have a generic title. Fixed-size windows cannot always fill a tile. Automatic Watch and snapshots only use accessible, visible, resizable windows outside full screen.
- Each app is responsible for exposing usable Accessibility information. Custom title bars can differ; swipe recognition uses the top 38 points while excluding common interactive controls.
- Saved layouts restore existing windows, not app processes or documents. Exact app/title matches are reserved first, then unmatched entries use the app's window order. Duplicate or changing titles can be ambiguous after an app restarts.
- Display restoration is debounced for two seconds after screen-configuration changes. Only one layout per display setup can be pinned.
- Watch polls approximately every 0.85 seconds. Undo captures manual moves while Quilt is running; moves during an application-driven layout transition can be grouped together.
- This implements the publicly advertised feature categories of 941 Tiles, with original code and interface. It is not its source code and has not been certified for behavioral parity.

## Validation status

Release build, bundle signature validation, twenty-five automated geometry/matching/window-creation/inventory/setup scenarios, app launch, visual interface inspection, and shortcut recording/default reset were checked locally. The new-window sequencing is tested with controlled cases (including delayed creation, timeout, cancellation, and apps that keep closing windows). An end-to-end test with a temporary native app started with two windows, requested six, opened exactly four more, and verified six non-overlapping actual window frames. Version 1.2 also verified two separate sets of six blank test windows on different real macOS desktop IDs, with no overlap within either set, plus preset editing and persistence across app restarts. Direct Codex UI testing is blocked by the computer-use tool. Other third-party apps, Watch, drag/drop, title-bar gestures, drawing placement, manual Undo, and physical multi-monitor reconnection require Accessibility permission and hands-on verification. These are implemented, but are not yet end-to-end verified on this Mac.

## Source layout

- `Sources/QuiltCore`: pure geometry and saved-window matching.
- `Sources/WindowQuilt`: Accessibility adapter, state/history, desktop control, setup editor, overlays, shortcuts, native views, menu-bar lifecycle.
- `Tests/QuiltCoreTests`: executable regression checks.
- `scripts`: build, test, and icon generation.

### Version 1.3 regression checks

`./scripts/test.sh` covers 25 scenarios, including hidden/minimized/full-screen inventory, keeping previous windows when AXWindows switches to another Space, exact creation counts, preservation policy, and migration of saved setups.

The native fixture in `Tests/WindowFixture/main.swift` disables automatic tabbing so it creates independent windows. Launch it with `--full-screen` to make each new window inherit full screen. The fixture writes its own frames, full-screen flags and Space IDs to `/private/tmp/quilt-window-fixture/windows.json`. After using Quilt to request three windows:

```sh
python3 Tests/WindowFixture/verify.py /private/tmp/quilt-window-fixture/windows.json --count 3
```

This live scenario passed with exactly three restored windows, one destination desktop, and no overlaps. A separate one-window run with Keep full screen matched the complete before/after report, including the original Space ID. Claude and Activity Monitor were restored and tiled through Quilt; Activity Monitor reports when its minimum size constrains the requested rectangle. These checks do not imply every third-party app or macOS version supports every window operation.

The minimized-window regression uses `--minimized`. On this macOS release, a minimized document window can temporarily report AXDialog; the inventory distinguishes that state from a modal dialog.

### Version 1.4 interface polish

Arrange and saved layouts now share concentric cards, clearer primary buttons, selected window rows, state badges, consistent SF Symbols, and restrained press feedback. Empty and loading states provide clearer guidance. Existing preferences and saved setups are retained. See [UI_POLISH.md](UI_POLISH.md) for the principle-by-principle review and verification limits.

### Version 1.5 workflow improvements

Arrange keeps Open & Tile and the destination summary visible while you scroll. Quick window counts, grouped destination controls, a compact preview, and expandable window behavior make setup faster. Save setup opens a prefilled editor. Saved setups support Undo for the last deletion while the Layouts view remains open. Keyboard actions and frequent count changes use immediate feedback. See [UX_REVIEW.md](UX_REVIEW.md) for the before/after review and validation scope.

### Version 1.6 active layouts

The **Active layouts** sidebar page manages live window sets. Edit a set's count and grid, choose which windows to keep when shrinking, or close the set together. Exact membership keeps other layouts isolated, including sets of the same app on one desktop. Existing windows are detected by app and desktop; new sets are tracked across Quilt restarts. Native close actions stop at app refusals or save prompts. See [ACTIVE_LAYOUTS.md](ACTIVE_LAYOUTS.md) for behavior, discovery limits, and verification.


### Version 1.7 simplified interface

The menu-bar picker now lists live sets under **Open panes**, with a **+** button to open one additional window and rearrange that set, and an **×** button to close every window in that set in one click. The live count and desktop identify each set, including separate sets of the same app. Saved setups remain available below. Adding a pane preserves the live layout's grid and destination without changing its saved preset; closing stops at app save prompts. Controls are disabled during an operation, and adding is limited to 40 panes per set.

The picker uses transient popover behavior so switching apps dismisses it. `bash scripts/test-popover.sh` is a native regression check that opens the real controller and switches to Finder; run it in a logged-in desktop session. It failed with the old semitransient behavior and passed with transient behavior.

- The main window opens to visual saved-setup cards; first-time users see the grid picker immediately.
- The menu bar uses a native popover with the same grid → app workflow. Apps have real icons, search, recent ordering, and an installed-app fallback.
- Click a grid square or drag from the top-left to choose count and shape together. Automatic and larger custom configurations remain supported under Options.
- Options is collapsed initially. Desktop, display, spacing, full-screen policy, fresh windows, and custom counts remain available. Changes affect the draft until **Use as defaults** is explicitly selected.
- Settings includes a collapsed arrangement-defaults editor. Tools preserves active layouts, per-window selection, Watch, snapshots, keyboard shortcuts, and help.
- Saving, editing, and running use the same arrangement view. Status, Stop, and Undo remain accessible during operations. Saved setup data is compatible with earlier versions.
- See [SIMPLIFIED_UI.md](SIMPLIFIED_UI.md) for validation and the live placement limitation observed during this pass.


### Version 1.7.1 menu-bar placement

Fixed the menu-bar popover extending above the display. AppKit now owns the hosting dimensions before presentation, and the panel is anchored below its own menu-bar button and constrained to that display. The saved/open-set list uses a compact height based on its contents; the arrangement flow expands within the same screen boundaries. Existing setup/default data is unchanged. See [POPOVER_FIX.md](POPOVER_FIX.md) for the reproduced failure and native regression checks.
