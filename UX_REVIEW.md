# Tilez 1.5 — design engineering pass

Applied the emil-design-eng skill to the frequent Arrange workflow and saved-setup recovery. The design retains native controls, teal surfaces, and the existing window-management engine.

| Before | After | Why |
| --- | --- | --- |
| Open & Tile appeared before the arrangement controls and scrolled out of reach. | A pinned action bar shows the requested app/count and desktop beside Open & Tile and Save setup. | Keep the consequence visible and the main action reachable throughout the flow. |
| Changing a count required repeated clicks on a small stepper. | One-click 1, 2, 4, 6, and 8 presets plus the existing 1–40 stepper; preview and summary update instantly. | Make the common path fast while retaining arbitrary counts. |
| Full-screen explanations and save-name fields crowded the initial screen. | An expandable behavior section retains a visible summary. Save setup opens the shared editor with the chosen values and a suggested name. | Progressive disclosure reduces initial reading while keeping important behavior visible. |
| Display selection lived below the grid, away from desktop selection. | Desktop and display controls are adjacent; New desktop explains that it creates a separate set accessed by swiping. | Group destination choices around the user's intent. |
| Existing-window actions competed visually with the create-and-tile action. | A distinct Open windows card contains selection, secondary Tile selected action, and Watch controls. | Explain the difference between tiling existing windows and requesting a total window count. |
| Deleting a saved setup had no recovery. | An inline Undo restores the most recently deleted setup at its former list position while the Layouts view remains open. | Make an accidental click recoverable without adding a confirmation dialog. |
| Shared press animation also applied to keyboard-driven state changes and static controls. | Pointer-only 0.96 press scale uses a 150 ms timing curve (0.23, 1, 0.32, 1). Keyboard, static, disabled, and reduced-motion paths bypass it. | Frequent keyboard interaction should be immediate; pointer feedback has a clear purpose. |

## Validation

- Release build and bundle signature validation passed.
- All 25 core scenarios passed: 39,556 assertions. The window-opening, tiling, Spaces, and persistence model files were unchanged.
- Native light interface checked at 900 × 752: initial configuration and grid, quick count selection, custom grid, expandable behavior controls, and the existing-window list with the action bar pinned during scrolling.
- Six-window preset updated the preview and summary immediately. Save setup populated the editor with six windows, three columns, and the existing destination/display/spacing values.
- Created a temporary setup, deleted it, restored it with Undo, confirmed its values and position, and removed the test setup. The user's original setup was retained.
- Restored the original eight-window count, automatic grid, and other arrangement preferences after verification.
- Inspected pointer/keyboard/disabled/reduced-motion branches in code. No staged entrances, navigation animations, or gesture animations were added.
- Not verified live in this pass: dark appearance, Reduce Motion preference, full keyboard-navigation focus, slow-motion playback, and opening/cancelling/tiling real windows. Those operations retain their existing engine; the changed UI handlers invoke the same operations. This pass does not extend the earlier release's end-to-end compatibility claims.

## Files

- `Sources/Tilez/Views.swift`: Arrange workflow, pinned actions, configured setup editor entry, accessible preview.
- `Sources/Tilez/SetupsView.swift`: setup deletion recovery and shared editor.
- `Sources/Tilez/TilezStyle.swift`: pointer-only press feedback.
- `scripts/build.sh`: version 1.5, build 6.
