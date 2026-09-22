# UI polish follow-up — September 14, 2026

Implemented with the better-ui skill, retaining SwiftUI/AppKit, the teal palette, and existing density. This report covers shared controls, navigation, window rows, and grid previews. Concurrent setup-editor and snapshot workflow changes are documented separately in SETUP_UX_REVIEW.md.

**Shadows for elevation, borders for structure**

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/Tilez/TilezStyle.swift:88 | Secondary buttons used a flat primary-color outline, unlike the surrounding cards. | Neutral edge ring and two transparent shadow layers in light mode; a white ring in dark mode. Disabled buttons lose elevation. Focus retains its explicit accent outline. | Consistent elevation separates actions from their surfaces without competing with focus or selection. Applies to all TilezButtonStyle secondary buttons. |

**Concentric corners and surface ownership**

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/Tilez/TilezStyle.swift:139; Sources/Tilez/Views.swift:37 | Navigation nested a padded selected background inside a separately padded hover/focus button surface. | One full-width 38-point navigation surface owns selected, pressed, hover, and focus states. | A single surface keeps corners and feedback aligned as the user moves between pages. |
| MEDIUM | Sources/Tilez/Views.swift:381; Sources/Tilez/Views.swift:273; Sources/Tilez/SetupsView.swift:61; Sources/Tilez/SetupsView.swift:183 | Tiles floated in a wide wash with no visible display boundary; preview math subtracted two extra points from every tile and only centered horizontally. Background styling was repeated at call sites. | A centered display bezel frames proportional tiles, using a 3-point tile radius plus 6-point bezel for a 9-point outer radius. The shared preview owns its background. Grid gaps are scaled directly from geometry, and labels disappear when tiles cannot fit them. | A clear display surface makes the arrangement easier to interpret, preserves real spacing, and fits the editor's narrower preview area. The asymmetric outer preview area retains its established 8-point token. |

**Icon alignment and weight**

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | Sources/Tilez/TilezStyle.swift:129; Sources/Tilez/TilezStyle.swift:194; Sources/Tilez/Views.swift:486 | Label icons lacked a shared alignment column; selected window icons became heavier than their adjacent text; snapshot delete used the generic button treatment. | Action labels share a 16-point icon column and 8-point gap. Window symbols retain regular weight, with color and checkbox state communicating selection. Snapshot restore/delete use the same SF Symbol and destructive treatment as saved setups. | Matching symbol weight and alignment reduces small visual jumps and makes action roles consistent. |

**Motion restraint and press feedback**

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | Sources/Tilez/TilezStyle.swift:10; Sources/Tilez/TilezStyle.swift:122; Sources/Tilez/TilezStyle.swift:209 | Press timing used a custom curve instead of the prescribed ease-out; unselected window rows had no pointer feedback. | Exactly 0.96 press scale with 150 ms ease-out, retaining static, keyboard, and reduced-motion opt-outs. Window-row hover and navigation feedback are immediate. | Frequent interactions stay quiet; selection remains visible through checkbox, color, and outline without animation. |

**Verification**

- Release build succeeded, and the final rebuilt app was relaunched and visually inspected. Bundle signature verified with `codesign --verify --deep --strict`.
- All 25 core scenarios passed: 39,556 assertions covering geometry, matching, creation, visibility, and saved setups. No new implementation-mirroring tests were added for cosmetic controls.
- Live light appearance: Arrange navigation and preview, saved setup cards, snapshot card/actions, setup editor at top and scrolled to Window behavior. The preview and Save/Cancel footer remain visible.
- An unsaved setup draft was increased from 8 to 40 windows; its preview fit. Clearing its name showed an explanation and disabled Save. Escape canceled the draft; no setup was saved.
- All/None selection verified the row states and disabled Tile selected at zero. All was restored afterward. No windows were tiled or snapshots changed during these checks.
- Code inspected for normal, hover, pressed, focused, disabled, selected/unselected, static and reduced-motion shared-control states; preview geometry, small-tile labels and invalid display-size fallback; existing loading/cancel and empty-state branches. No added page-load or theme animations. Animation is scoped to the press-state value.
- **Not verified:** live dark appearance or theme switching, full keyboard-focus navigation, OS Reduce Motion behavior, loading/cancellation during an actual arrangement, live empty collections, portrait displays, smallest-window-size layout, and motion playback at 10% speed. This is a native application with no browser Animations panel. Hover styling was inspected in code; isolated hover and held-press screenshots were not captured.
- An optional separate scratch build failed because its default Clang cache was outside the writable sandbox. The repository's build script supplies a writable module cache and passed; this does not affect the delivered app.

No unresolved HIGH findings in the inspected scope. Approval covers the implementation and checks above; the explicitly unverified states remain outside its coverage.

Approve
