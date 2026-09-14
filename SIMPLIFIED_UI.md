# Window Quilt 1.7 — simpler arrangement flow

The primary flow is now **choose a grid → choose an app**. Saved setups are visual cards in the main window and directly accessible from the menu-bar popover. There is no sidebar. Existing setup serialization and the window-management engine are retained.

| Before | After | Why |
| --- | --- | --- |
| App, count, automatic/custom mode, columns, and rows were separate decisions. | One clickable/draggable grid chooses count and arrangement; an icon-and-name app picker follows it. | Combine related decisions into a direct visual choice. |
| Five or more navigation sections competed with arranging windows. | Saved setups are the home screen; new users start at the grid. Tools contains active layouts, per-window arrangement, Watch, snapshots, shortcuts, and help. | Keep the frequent path short while preserving existing capabilities. |
| A text menu exposed app lists, grid settings, Watch, and movement submenus. | A native popover shares the arrangement view and shows saved setups. Its gear menu contains secondary commands. | Keep the menu-bar interaction consistent with the main window. |
| Destination and window behavior occupied the primary form. | Options starts collapsed. Desktop, display, spacing, fresh-window policy, full-screen policy, and custom counts remain available inside. | Make configuration optional. |
| Configuration edits immediately changed shared preferences. | New-flow edits affect a draft. Only **Use as defaults** persists the arrangement defaults. Existing saved setups retain their settings. | Separate trying a layout from changing future behavior. |
| Saved setups exposed Edit, Duplicate, Open, and Delete together. | Click the card to run; its menu contains maintenance actions. Deletion has Undo, including when the last setup is removed. | Give each card one primary action. |
| The setup editor was a separate long form. | Editing uses the same grid and folded options, with a name field and an optional app change. | Keep one interaction to learn. |
| A named desktop could show a conflicting display selection. | The selected desktop determines the displayed target screen and locks the redundant display picker. | Match the engine's existing destination rule. |

## Validation

- Release builds passed; core checks passed **30 scenarios / 39,569 assertions** covering geometry, matching, creation, visibility, setup persistence, and active-layout ownership.
- Focused in-memory preference checks passed: draft edits do not persist, explicit defaults round-trip into a new Preferences instance, and saved setups retain their original values. The checks never modify real user defaults.
- Native dark-mode inspection: setup library, creation sheet, selected six-window grid, collapsed/expanded options, scrolling with the main action pinned, app icons, and app search.
- Saved a temporary fixture setup, edited its name and grid without running it, restarted Quilt, and verified the changes persisted. Delete/Undo restored it; the temporary setup was then removed. The two original saved setups were retained.
- The new app-picker action reached the existing creation/tiling engine using the blank-window fixture. It selected six windows on the configured destination and left two windows on another desktop open, consistent with the existing desktop-scoped reuse policy.
- **Live placement check failed:** fixture telemetry showed overlapping windows after the engine reported size constraints, on both external-display and built-in-display trials. This does not establish correct end-to-end placement. No changes were made to Accessibility, geometry, desktop control, window creation, or active-layout ownership in this UI pass.
- Grid click selection was verified live. Dragging, the full menu-bar popover flow, keyboard-only navigation, light appearance, and explicit default persistence were inspected in code but not completely verified live; computer-use calls intermittently returned `noWindowsAvailable`, timeouts, or external-state changes. Do not interpret the passing core checks as coverage of these paths.

## Behavior details

- New arrangements inherit the user's existing preferences. No migration resets their defaults or saved setups.
- Grid selection supports up to 5 × 4 directly. Options → Custom window count and grid preserves the 1–40 count and 0–20 row/column ranges; zero remains automatic.
- App discovery checks standard installation folders and running apps, with an explicit file picker for applications elsewhere. Recent apps are remembered locally. The menu captures the previously focused app before activating Quilt.
- Saving the result saves the recipe; the engine's actual status is shown without inventing a success state. Stop remains available during creation. Undo restores placements; newly opened windows remain open.
- Saved setups with disconnected destinations remain editable. New arrangements require an available destination before proceeding.
