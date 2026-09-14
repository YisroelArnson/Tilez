# Setup and snapshot usability

Applied the emil-design-eng skill to setup editing, saved-workspace navigation, and operation recovery. Shared navigation, button, and preview polish was developed concurrently and preserved.

| Before | After | Why |
| --- | --- | --- |
| A 560 × 750 setup sheet put a long form above the preview and actions. | A 720-wide sheet uses a grouped scrolling form, persistent preview sidebar, and pinned Save/Cancel footer; its height is capped to the screen. | Keep the arrangement and exit actions visible while editing. |
| Save could be disabled without explaining the missing input. | Inline guidance identifies a missing name or app, and initial focus goes to the name. Names are trimmed on save. | Make the next step apparent and support keyboard entry. |
| Saved-setup previews assumed a 1920 × 1080 display. | Selected display bounds drive the preview, with an illustrative connected-display fallback. | Reflect portrait and other display proportions. |
| A saved destination could be unavailable without an explanation. | The editor marks unavailable destinations and explains that a destination must be chosen before opening. | Keep disconnected saved configurations editable without silently changing them. |
| The snapshots tab retained the Saved setups header and unrelated New Setup action. | The header follows the selected tab, and snapshots have their own Save Snapshot action. | Keep navigation and actions aligned with the current task. |
| New setup names referred to ChatGPT even when selecting Codex. | Suggested names use the application's actual display name. | Keep the saved name consistent with the chosen app. |
| Deleting a desktop snapshot had no recovery. | Inline Undo restores the most recently deleted snapshot at its former position while the snapshots view remains open. | Match saved-setup recovery without a confirmation dialog. |
| Failed snapshot saves cleared the typed name. | The name is cleared only when a snapshot is added. | Preserve user input on failure. |
| Snapshot save/restore and arrangement Undo remained available during window creation. | Those actions are disabled while opening windows; submission also guards against the busy state. | Avoid conflicting operations through these controls. |
| Cancellation was available in Arrange and the menu bar. | A global status-bar Cancel action remains available on every page during creation or setup launch. | Allow users to stop an operation after navigating away. |
| Window checkboxes did not explain how Open & Tile uses them. | The window list explains that checked windows are prioritized, then other available windows fill the count. | Distinguish preference ordering from the separate Tile selected action. |
| The pinned Arrange summary omitted the destination display. | Desktop and display are both included, with full text available on hover. | Make the intended destination inspectable before applying. |

Frequent edits and keyboard navigation remain immediate. No new animation was added in this scope. Window creation, geometry, desktop control, and persistence formats were not changed.

## Validation

- `./scripts/test.sh`: passed 25 scenarios and 39,556 assertions.
- Final incremental release build passed; `codesign --verify --deep --strict` passed.
- Coordinated native inspection on the final binary checked the editor at the top and scrolled to Window behavior: preview and Save/Cancel remain visible.
- A temporary editor draft was changed from 8 to 40 windows and its name cleared. The preview fit and Save was disabled with “Give this setup a name.” Escape cancelled without saving.
- Saved cards and the Desktop snapshots heading, Save Snapshot action, and existing card fit cleanly. No snapshots were changed.
- All/None selection was checked, Tile selected was disabled at zero, and All was restored. The app was left on Arrange.
- Snapshot delete/Undo, cancellation during real creation, unavailable destinations, dark appearance, and reduced-motion settings were reviewed in code but not exercised live in this pass. The core checks do not establish those UI paths end to end.
- Snapshot Undo preserves a newer automatic-restore selection for the same display topology by restoring the deleted snapshot with automatic restore off when necessary.
- Recovery is limited to the last snapshot deleted during the lifetime of the snapshots view, consistent with the existing saved-setup Undo behavior.
