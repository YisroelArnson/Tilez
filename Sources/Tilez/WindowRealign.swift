import AppKit
import TilezCore

/// ⌃⌥R tidies the windows on a display's current desktop in place, the same as ⌘R in the grid,
/// without opening it. Undo last window arrangement puts them back.
@MainActor enum WindowRealign {
    static func run(on display: Display, manager: WindowManager) async {
        guard let windows = await arrangeable(on: display, manager: manager) else { return }
        var grid = DesktopGrid.desktop(panes: windows.map { (GridSlot(), $0.frame) }, in: display.bounds)
        guard !windows.isEmpty, grid.slots.count == windows.count else { NSSound.beep(); return }
        // Reading the screen clips each window to it, so even windows too far out of line to
        // realign come back inside the screen instead of staying off its edge.
        let inside = grid.frames(in: display.bounds)
        let gap = CGSize(width: 10 / display.bounds.width, height: 10 / display.bounds.height)
        let aligned = grid.realign(gap: gap)
        let targets = aligned ? grid.frames(in: display.bounds) : inside
        let changes = zip(windows, targets).filter { !Geometry.fits($0.frame, in: $1) }
        guard !changes.isEmpty else { if !aligned { NSSound.beep() }; return }
        manager.recordArrangement(changes.map(\.0), label: "Realign windows")
        for (window, target) in changes { Task { await WindowMotion.move(window.element, to: target) } }
    }

    /// The windows on a display's current desktop that can be moved, front to back, read the way
    /// the grid reads them: every window, including those behind others. Nil after a beep when
    /// there's nothing to arrange there.
    static func arrangeable(on display: Display, manager: WindowManager) async -> [ManagedWindow]? {
        guard Accessibility.trusted else { Accessibility.requestPermission(); return nil }
        guard let desktop = Desktops.current(displayID: display.id, includeFullScreen: true), !desktop.isFullScreen else {
            NSSound.beep(); return nil
        }
        let captured = GridEditorModel.captureDesktop(display: display, desktop: desktop, manager: manager)
        let pids = Set(captured.slots.compactMap { $0.binding?.windowID.split(separator: ":").first.flatMap { Int32($0) } })
        guard !pids.isEmpty, (try? await manager.refresh(for: pids)) != nil else { NSSound.beep(); return nil }
        let live = Dictionary(manager.windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return captured.slots.compactMap { slot -> ManagedWindow? in
            guard let id = slot.binding?.windowID, let window = live[id] else { return nil }
            let onDisplay = display.bounds.intersection(window.frame)
            return window.availability.automatic && !onDisplay.isNull && onDisplay.width > 1 && onDisplay.height > 1 ? window : nil
        }
    }

    /// Moves each window to its frame with the usual glide, as one undoable arrangement.
    static func move(_ changes: [(ManagedWindow, CGRect)], label: String, manager: WindowManager) {
        let changes = changes.filter { !Geometry.fits($0.0.frame, in: $0.1) }
        guard !changes.isEmpty else { return }
        manager.recordArrangement(changes.map(\.0), label: label)
        for (window, target) in changes { Task { await WindowMotion.move(window.element, to: target) } }
    }
}
