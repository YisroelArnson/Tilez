import AppKit
import TilezCore

/// ⌃⌥R tidies the windows on a display's current desktop in place, the same as ⌘R in the grid,
/// without opening it. Undo last window arrangement puts them back.
@MainActor enum WindowRealign {
    static func run(on display: Display, manager: WindowManager) async {
        guard Accessibility.trusted else { Accessibility.requestPermission(); return }
        guard let desktop = Desktops.current(displayID: display.id, includeFullScreen: true), !desktop.isFullScreen else {
            NSSound.beep(); return
        }
        // Read the desktop the way the grid does, so buried windows don't become panes.
        let captured = GridEditorModel.captureDesktop(display: display, desktop: desktop, manager: manager)
        let visible = DesktopGrid.visibleDesktop(panes: Array(zip(captured.slots, captured.frames(in: display.bounds))),
                                                 in: display.bounds)
        let pids = Set(visible.slots.compactMap { $0.binding?.windowID.split(separator: ":").first.flatMap { Int32($0) } })
        guard !pids.isEmpty, (try? await manager.refresh(for: pids)) != nil else { return }
        let live = Dictionary(manager.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = visible.slots.compactMap { slot -> ManagedWindow? in
            guard let id = slot.binding?.windowID, let window = live[id] else { return nil }
            let onDisplay = display.bounds.intersection(window.frame)
            return window.availability.automatic && !onDisplay.isNull && onDisplay.width > 1 && onDisplay.height > 1 ? window : nil
        }
        var grid = DesktopGrid.desktop(panes: windows.map { (GridSlot(), $0.frame) }, in: display.bounds)
        let gap = CGSize(width: 10 / display.bounds.width, height: 10 / display.bounds.height)
        guard !windows.isEmpty, grid.realign(gap: gap) else { NSSound.beep(); return }
        let changes = zip(windows, grid.frames(in: display.bounds)).filter { !Geometry.approximatelyEqual($0.frame, $1) }
        guard !changes.isEmpty else { return }
        manager.recordArrangement(changes.map(\.0), label: "Realign windows")
        for (window, target) in changes { Task { await WindowMotion.move(window.element, to: target) } }
    }
}
