# Tilez 1.6 — active layouts

Use **Active layouts** in the sidebar to search for an app or layout and manage its current windows.

- **Edit…** changes the set's name, count, columns, rows, spacing, and full-screen policy. Reducing the count selects windows to keep; change those checkboxes to choose which windows close. A review step confirms the number being closed.
- Increasing a tracked set opens missing windows and cannot borrow existing windows from another set, including another set on the same desktop.
- **Close set…** closes only the listed members. Tilez uses their native close buttons, never quits the app or discards save prompts. Closing is not part of Tilez's arrangement Undo history. A refusal or dialog stops the batch; already completed closes are not rolled back.
- Active edits affect the running set. They do not overwrite a saved setup template.
- Newly opened layouts retain exact window IDs and the app's process-launch identity across Tilez restarts. Membership reconciles as windows close; a restarted app cannot inherit stale destructive targets.
- Existing windows are detected by app and desktop. Historical sets sharing the same app and desktop cannot be reconstructed automatically; they appear as one detected set. Once tracked, separate sets on the same desktop remain distinct. Windows with ambiguous Space membership appear separately.

## Design review

| Before | After | Why |
| --- | --- | --- |
| Saved templates did not show which sets were running. | A searchable Active layouts view with current counts and desktop labels. | Distinguish reusable configurations from their live windows. |
| Each window had to be closed individually. | Close set with a concrete member count and review dialog. | Manage the group while keeping the destructive scope explicit. |
| Requesting fewer windows left extras open. | Active-set editing closes unchecked members and tiles the retained set. | Make an eight-to-six change mean exactly what the user expects. |
| App-wide matching could mix different sets. | Exact membership with process-session validation and restricted growth. | Keep neighboring layouts isolated. |

## Validation performed

- Release build and signature verification.
- 30 core scenarios, 39,569 assertions: existing geometry, window discovery/creation, saved setups, plus active membership, shrink isolation, same-desktop growth eligibility, process restarts, ownership transfer, stable ordering, and persistence.
- Native discovery identified the user's existing two sets as eight ChatGPT/Codex windows on each of two desktops. The user subsequently reduced one to six during development; the agent did not operate on those windows.
- Native fixture: created separate tracked sets on the same desktop, requested eight-to-six, and verified exactly two closed with six remaining. Every other-set window identity and frame was unchanged.
- Native fixture: closed all six members of that set; all seven surviving windows in its neighboring set and their frames were unchanged. (That neighbor had seven following the earlier failing close-detection reproduction.)
- Native fixture: grew a two-window set to four while another two-window set existed on the same desktop. Exactly two new window IDs appeared; the neighboring set and frames stayed unchanged.
- Native fixture: a close refused by an app confirmation stopped the batch, left both windows open, and left the confirmation untouched.
- Restarted Tilez and verified tracked identities/counts survived. Restarting the fixture removed old process membership; its new windows were detected afresh.
- Native light UI: cards, filtering, editor, count/keep selection, destructive review, empty search results, and operation status inspected.

The native fixture exposed an AppKit edge case: a closed but retained NSWindow can remain in WindowServer. Close completion also checks that the window is absent from a responsive app's AXWindows while its Space is still current and the app remains unhidden. Confirmed closures are excluded from fallback inventory, tied to the app's launch identity; a reopened window exposed through Accessibility clears the exclusion.

Not verified in this pass: every third-party app's close/save behavior, live full-screen batch closing, dark appearance, reduced-motion settings, and interactive cancellation halfway through a batch. App minimum sizes can still constrain dense grids; those constraints are reported rather than treated as exact geometry success.

`Tests/ActiveLayoutFixture/main.swift` is a disposable native fixture, with an optional `/private/tmp/tilez-active-fixture/block-close` marker to present a confirmation instead of closing. It writes its window IDs, frames and Spaces to `/private/tmp/tilez-active-fixture/windows.json`. After recording the named before/after reports for the scenarios above, run:

```sh
python3 Tests/ActiveLayoutFixture/verify.py /private/tmp/tilez-active-fixture
```

The verifier checks actual window identities, counts, and unchanged neighboring frames. It does not drive the GUI or claim a fresh end-to-end run from archived reports.
