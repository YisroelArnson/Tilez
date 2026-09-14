# Window Quilt 1.4 UI polish

Applied the better-ui skill to the native SwiftUI interface, preserving its teal identity and existing controls. All rows below describe implemented fixes. Paths are relative to this project.

## Concentric corners and surface depth

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/WindowQuilt/QuiltStyle.swift:19; Sources/WindowQuilt/Views.swift:191,222,245,381; Sources/WindowQuilt/SetupsView.swift:57 | Cards used inconsistent radii and insets, with flat border-based separation. | Shared 24-point outer corners, 16-point padding and 8-point inner corners; neutral ring and layered transparent shadows. | Concentric radius and elevation principles make nested previews and cards feel coherent. Selected and focus borders retain their structural meaning. |

## State clarity and restrained interaction feedback

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | Sources/WindowQuilt/QuiltStyle.swift:69,118; Sources/WindowQuilt/Views.swift:59,177,241,251,360; Sources/WindowQuilt/SetupsView.swift:19,41,133 | Pale primary actions and plain window rows provided weak visual hierarchy. | Deep teal primary buttons, distinct disabled states, selected row wash and outline, and compact window-state badges. | Static state cues make selection and available actions clear without relying on motion. |
| LOW | Sources/WindowQuilt/QuiltStyle.swift:50; Sources/WindowQuilt/Views.swift:40,90,177,228,229; Sources/WindowQuilt/SetupsView.swift:136 | Button feedback varied across surfaces. | Shared 0.96 press scale with 150 ms ease-out, hover tint, focus outline, and static/reduced-motion opt-outs. | Scale-on-press and motion restraint provide consistent feedback. Animation is scoped to pressing; page loads and theme changes have no added animation. |
| LOW | Sources/WindowQuilt/Views.swift:76,175,235 | A green footer indicator could imply success regardless of status; opening replaced the action; empty lists offered little guidance. | Informational status icon, native busy indicator, a stable minimum-width action that becomes Cancel opening, and an explicit empty state. | State changes retain persistent text and visual cues, reducing ambiguity and layout movement. |

## Icon weight and alignment

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| LOW | Sources/WindowQuilt/QuiltStyle.swift:85,108,125; Sources/WindowQuilt/Views.swift:36,81,125,126,132,174,186,195,226,250; Sources/WindowQuilt/SetupsView.swift:19,40,47,51,55 | Actions mixed text-only controls and inconsistently emphasized symbols. | Native SF Symbols share the text weight, active navigation uses filled variants, and icon-only controls have 32-point minimum targets and accessible labels. | A single native icon family keeps visual weight and alignment consistent. The grid symbol was checked against AppKit and corrected to square.grid.3x2. |

## Verification

- Release build succeeded; all 25 automated core scenarios passed (39,556 assertions).
- Inspected the native light interface: Arrange, saved setup cards, setup editor, selected/unselected rows, disabled actions, and an empty window list. Editor Escape cancellation works; the saved setup was preserved.
- Read all shared button states in code: normal, hover, focused, pressed, disabled, static and reduced motion. Inspected loading/cancellation labels and empty-state code. Checked the exact scale, duration, easing and animation scope.
- Existing window-manager logic was unchanged. The Open & Tile button now dispatches cancellation while its app is opening; otherwise it uses the same opening operation and parameters.
- **Not verified:** live dark appearance, the macOS Reduce Motion preference, custom button focus with full keyboard navigation, live loading/cancellation presentation during window arrangement, and animation playback at 10% speed. This native app has no browser Animations panel. These remain outside the visual approval coverage.

No unresolved HIGH findings in the inspected scope. Approval covers the implemented changes and checks above, not the explicitly unverified coverage.

Approve
