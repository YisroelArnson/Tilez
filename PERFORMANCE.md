# Grid responsiveness

The editor was still running the legacy all-application inventory timer every 850 ms even with background arrangements disabled. Each scan used synchronous Accessibility IPC on the main thread. Opening the editor also synchronously walked application directories; grid launch repeated whole-system scans and waited 900 ms for each app, including existing windows.

The grid mode now disables the legacy timer and startup scan. Application discovery runs in the background and caches its results for 60 seconds. Grid inventory reads, New Window menu lookup, placement, and frame verification use a serial Accessibility worker. Inventory requests are restricted to the apps being arranged. Existing windows bypass the new-window transition delay, while new windows retain the full-screen transition safeguard. Readiness polling is faster while preserving its ten-second polling budget.

Measured on this Mac using `bash scripts/test-grid-editor.sh --require-display`:

| Check | Before | After |
| --- | --- | --- |
| First `GridEditorModel.begin` call | 129.7 ms | 3.6–5.2 ms |
| Repeat begin calls | 10.4–12.2 ms | 0.5–7.5 ms |
| Idle inventory publications in 1.1 seconds | 1 (regression failed) | 0 |

These timings measure editor initialization, not end-to-end frame rendering or third-party application launch time. A regression check also simulates a 100 ms AX operation and verifies that main-actor input handling runs before it finishes. Cancellation and asynchronous catalog publication/cache reuse are covered.

Validation:

- `bash scripts/test.sh`: passed all core and preferences checks (39,696 core assertions).
- `bash scripts/test-grid-editor.sh --require-display`: passed editor behavior and responsiveness checks.
- `bash scripts/build.sh`: release build and signing passed.
- Installed build: app search, applying the existing four-window ChatGPT grid, and reopening with Control–Option–Space worked. Two simultaneously running copies were consolidated into the installed app.

The source tree also received concurrent UI edits during this work; they were preserved. New-window full-screen transitions were not exercised in the live smoke check.

## Live-pane editor follow-up

Opening the editor now starts with a WindowServer snapshot instead of a remembered draft. Accessibility refinement is asynchronous and cannot overwrite edits. Pane geometry updates make no Accessibility calls or preference writes while dragging.

The final checks measured live desktop capture at 3.3–9.9 ms and 60 divider-preview updates at 1.4–2.2 ms. The geometry suite completed 500 divider edits in 21.7–25.5 ms. These are model/capture timings, not GPU frame-rate measurements.

Added coverage includes empty and single-window desktops, six existing panes, unequal and overlapping geometry, occlusion by multiple front windows, splits, T-junction dividers, pane removal, exact-window swaps, legacy template decoding, cancellation, and explicit new-window requests that exclude unrelated existing windows. The suite passed 39,762 core assertions plus editor and keyboard checks.

Native checks exercised live import on multiple desktops, an edge split, app search and assignment, draft undo, and a single native full-screen test window. Applying from full screen restored that exact window and created a new window while leaving an unrelated test window unchanged. A placement failure exposed stale full-screen work-area bounds and new-window settling; bounds are now refreshed after the transition and only unsettled placements are retried. The final retry behavior is covered by deterministic tests (including a window that rejects the first two retries); the complete final retry sequence was not rerun natively because UI automation timed out while addressing the test app’s full-screen Space. The disposable test processes were stopped afterward.
