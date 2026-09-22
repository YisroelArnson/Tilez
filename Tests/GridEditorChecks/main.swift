import AppKit
import Combine
import SwiftUI
import TilezCore

// Render the production toolbar preview, not a separate geometry approximation.
MainActor.assumeIsolated {
    let app = GridApp(bundleID: "preview.test", name: "Preview")
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let panes = Geometry.grid(count: 6, in: bounds, columns: 3, rows: 2, gap: 10).map { (GridSlot(app: app), $0) }
    var grid = DesktopGrid.desktop(panes: panes, in: bounds)
    for stage in ["six panes", "split", "removed", "empty"] {
        if stage == "split" { let index = grid.split(0, toward: .bottom)!; grid.slots[index].app = app }
        if stage == "removed" { grid.removePane(1) }
        if stage == "empty" { grid = .emptyDesktop }
        let renderer = ImageRenderer(content: GridLayoutPreview(grid: grid, selectedCell: 0))
        renderer.scale = 3
        guard let image = renderer.cgImage else { fatalError("Layout preview did not render") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        for (index, frame) in grid.frames(in: CGRect(x: 5, y: 5, width: 75, height: 49), gap: 2).enumerated() {
            let color = bitmap.colorAt(x: Int(frame.midX * 3), y: Int(frame.midY * 3))!.usingColorSpace(.deviceRGB)!
            let isFilled = color.redComponent < 0.5
            assert(isFilled == (grid.slots[index].app != nil), "Preview must draw actual pane positions: \(stage), pane \(index)")
        }
    }
    print("PASS: rendered toolbar preview matches six panes, uneven splits, removal, and an empty desktop")
}

final class GridMemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

MainActor.assumeIsolated {
    let storage = GridMemoryDefaults(suiteName: nil)!
    let manager = WindowManager(preferences: Preferences(defaults: storage), backgroundArrangements: false)
    let model = GridEditorModel(manager: manager, defaults: storage)
    let safari = GridApp(bundleID: "com.apple.Safari", name: "Safari")
    let finder = GridApp(bundleID: "com.apple.finder", name: "Finder")
    let binding = GridWindowBinding(windowID: "old-window", processSession: "old-launch")
    model.grid = DesktopGrid(slots: [GridSlot(app: safari, binding: binding)])
    model.choose(1); model.assign(finder)
    assert(model.grid.slots[1].app == finder && !model.choosingApp)
    model.move(from: 0, to: 2, repeating: true)
    assert(model.grid.slots[2].app == safari && model.grid.slots[2].binding == nil)
    model.move(from: 0, to: 1, repeating: false)
    assert(model.grid.slots[1].binding == binding && model.grid.slots[0].app == finder)
    model.undo()
    assert(model.hasOpened, "Undo restores the Apply grid state along with live bindings")
    assert(model.grid.slots[0].binding == binding && model.grid.slots[1].app == finder)
    model.saveName = "Mixed apps"; model.save()
    assert(model.saved.count == 1 && model.saved[0].grid.slots.allSatisfy { $0.binding == nil })
    model.newGrid()
    assert(model.grid.filledCount == 0)
    model.load(model.saved[0])
    assert(model.grid.filledCount == 3 && model.grid.slots[1].app == finder)
    model.clear(1)
    assert(model.grid.slots[1].app == nil)
    model.undo()
    assert(model.grid.slots[1].app == finder)
    let restored = GridEditorModel(manager: manager, defaults: storage)
    assert(restored.saved == model.saved, "Saved grids survive app restart")
    restored.deleteSaved(restored.saved[0].id)
    assert(GridEditorModel(manager: manager, defaults: storage).saved.isEmpty)
    model.busy = true
    let unchanged = model.grid
    model.resize(columns: 1, rows: 1)
    model.assign(finder)
    model.clear(0)
    model.move(from: 0, to: 1, repeating: false)
    assert(model.grid == unchanged, "Opening freezes grid edits")
    print("PASS: app selection, live-window swaps, repeat, undo, saved-grid persistence, loading, deletion, and editing during launch")
}

// The grid editor must not poll every application while the user is editing.
// Count inventory publications so this catches work even without AX permission.
MainActor.assumeIsolated {
    let storage = GridMemoryDefaults(suiteName: nil)!
    let started = Date()
    let manager = WindowManager(preferences: Preferences(defaults: storage), backgroundArrangements: false)
    print(String(format: "PERF: manager startup %.1f ms", Date().timeIntervalSince(started) * 1_000))
    let model = GridEditorModel(manager: manager, defaults: storage)
    if let display = Display.all.first {
        for attempt in 1...3 {
            let start = Date()
            model.begin(on: display, snapshot: .emptyDesktop)
            let elapsed = Date().timeIntervalSince(start)
            print(String(format: "PERF: editor begin %d: %.1f ms", attempt, elapsed * 1_000))
            assert(elapsed < 0.1, "Showing the editor must not wait for application discovery")
        }
        assert(model.loadingApps, "Application discovery must yield to the event loop")
        assert(model.selectedCell == 0, "A new desktop starts with the first empty cell selected")
        model.grid = DesktopGrid()
        model.selectedCell = 3
        model.persist()
        model.begin(on: display, snapshot: .emptyDesktop)
        assert(model.selectedCell == 0 && model.grid == .emptyDesktop, "An empty desktop replaces the old draft and clamps selection")
    } else {
        assert(!CommandLine.arguments.contains("--require-display"), "A macOS display is required for editor latency checks")
        print("SKIP: editor latency checks require access to a macOS display")
    }
    var publications = 0
    let subscription = manager.$windows.dropFirst().sink { _ in publications += 1 }
    RunLoop.main.run(until: Date().addingTimeInterval(1.1))
    withExtendedLifetime(subscription) {}
    print("PERF: idle inventory publications: \(publications)")
    fflush(stdout)
    assert(publications == 0, "Grid editing must not run all-app inventory scans on the main thread")
}

var asyncChecksFinished = false
Task { @MainActor in
    // Exercise the same AX execution boundary used by scans, menu commands, and moves.
    var inputHandled = false
    let input = Task { @MainActor in
        try await Task.sleep(nanoseconds: 20_000_000)
        inputHandled = true
    }
    let ranOnMainThread = try await Accessibility.perform {
        Thread.sleep(forTimeInterval: 0.1) // Simulate a slow/unresponsive application.
        return Thread.isMainThread
    }
    assert(!ranOnMainThread && inputHandled, "A slow AX call must not block editor input")
    _ = try await input.value
    let cancelled = Task { @MainActor in
        try await Accessibility.perform { () -> Bool in fatalError("Cancelled work must not begin") }
    }
    cancelled.cancel()
    do { _ = try await cancelled.value; assertionFailure("Cancellation must propagate") }
    catch is CancellationError {} catch { assertionFailure("Unexpected error: \(error)") }
    let storage = GridMemoryDefaults(suiteName: nil)!
    let manager = WindowManager(preferences: Preferences(defaults: storage), backgroundArrangements: false)
    let model = GridEditorModel(manager: manager, defaults: storage)
    if let display = Display.all.first {
        model.begin(on: display, snapshot: .emptyDesktop)
        let deadline = Date().addingTimeInterval(10)
        while model.loadingApps && Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        assert(!model.loadingApps && !model.apps.isEmpty, "Background catalog discovery must publish the available apps")
        let apps = model.apps.map(\.id)
        model.begin(on: display, snapshot: .emptyDesktop)
        assert(!model.loadingApps && model.apps.map(\.id) == apps, "Reopening must reuse the fresh catalog")
    }
    print("PASS: slow AX work leaves input responsive, cancellation, background app discovery, cached reopening")
    asyncChecksFinished = true
}
let asyncDeadline = Date().addingTimeInterval(20)
while !asyncChecksFinished && Date() < asyncDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
assert(asyncChecksFinished, "Responsiveness checks did not finish")

MainActor.assumeIsolated {
    let storage = GridMemoryDefaults(suiteName: nil)!
    let manager = WindowManager(preferences: Preferences(defaults: storage), backgroundArrangements: false)
    let model = GridEditorModel(manager: manager, defaults: storage)
    let safari = GridApp(bundleID: "com.apple.Safari", name: "Safari")
    let finder = GridApp(bundleID: "com.apple.finder", name: "Finder")
    let live = GridWindowBinding(windowID: "window-a", processSession: "session-a")
    let other = GridWindowBinding(windowID: "window-b", processSession: "session-b")
    @MainActor func key(_ code: UInt16, _ text: String = "", _ modifiers: NSEvent.ModifierFlags = [], editing: Bool = false) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        return model.handleKey(event, editingText: editing)
    }
    for code: UInt16 in [123, 124, 125, 126] {
        model.grid = DesktopGrid(columns: 1, rows: 1, slots: [GridSlot(app: safari, binding: live)])
        model.selectedCell = 0
        let beforeSplit = model.grid
        assert(key(code, "", .option) && model.grid.slots.count == 2 && model.selectedCell == 1 && model.choosingApp,
               "Option–Arrow splits and opens the new pane's app chooser")
        assert(model.grid.slots[0].binding == live && model.grid.slots[1].app == nil,
               "Splitting preserves the original window and creates an empty pane")
        let frames = model.grid.normalizedFrames
        switch code {
        case 123: assert(frames[1].maxX <= frames[0].minX)
        case 124: assert(frames[1].minX >= frames[0].maxX)
        case 125: assert(frames[1].minY >= frames[0].maxY)
        default: assert(frames[1].maxY <= frames[0].minY)
        }
        let split = model.grid
        assert(!key(code, "", .option, editing: true) && model.grid == split,
               "Option–Arrow preserves native word navigation inside the chooser")
        assert(key(53) && key(6, "z", .command) && model.grid == beforeSplit,
               "A keyboard split is a single undo step")
        assert(!key(code, "", .option, editing: true) && model.grid == beforeSplit,
               "Text fields must not split panes")
        model.busy = true
        assert(!key(code, "", .option) && model.grid == beforeSplit, "Applying blocks keyboard splits")
        model.busy = false
    }
    model.grid = .emptyDesktop
    model.selectedCell = nil
    assert(key(124, "", .option) && model.grid.slots.count == 2,
           "An empty desktop can be split without selecting a pane first")
    assert(key(53)); model.undo()
    model.grid = DesktopGrid(columns: 3, rows: 2, slots: [GridSlot(app: safari, binding: live), GridSlot(app: finder, binding: other)])
    model.selectedCell = 0
    assert(key(124, "", .shift))
    assert(model.selectedCell == 1 && model.grid.slots[1].binding == live && model.grid.slots[0].binding == other,
           "Shift–Arrow swaps exact window assignments and follows the moved window")
    assert(key(124, "", [.command, .shift]))
    assert(model.selectedCell == 2 && model.grid.slots[2].app == safari && model.grid.slots[2].binding == nil,
           "Command–Shift–Arrow copies an app, never its window binding")
    let copied = model.grid
    assert(key(123, "", [.command, .shift]))
    assert(model.grid == copied && model.selectedCell == 1, "Copying onto the same app only follows it, keeping its live window")
    model.selectedCell = 2
    for modifiers: NSEvent.ModifierFlags in [[], .shift, [.command, .shift]] {
        assert(key(124, "", modifiers))
        assert(model.grid == copied && model.selectedCell == 2, "Right edge cannot wrap to the next row")
    }
    assert(key(125, "", .shift))
    assert(model.selectedCell == 5 && model.grid.slots[2].app == nil && model.grid.slots[5].app == safari,
           "Shift–Arrow moves into empty cells")
    assert(key(6, "z", .command))
    assert(model.grid == copied, "Undo reverses the complete keyboard move")
    model.selectedCell = 0
    assert(key(126) && model.selectedCell == 0)
    assert(key(123) && model.selectedCell == 0)
    model.apps = [GridAppChoice(app: safari, url: URL(fileURLWithPath: "/Applications/Safari.app")),
                  GridAppChoice(app: finder, url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))]
    assert(key(3, "f") && model.choosingApp && model.search == "f")
    assert(key(34, "i") && model.search == "fi", "Fast typing survives search focus transfer")
    model.search = ""
    assert(key(125, editing: true) && model.selectedAppChoice?.app == finder)
    assert(!key(123, "", .shift, editing: true), "Search preserves Shift–Arrow text selection")
    assert(!key(124, "", [.command, .shift], editing: true), "Search preserves Command–Shift–Arrow text selection")
    assert(!key(6, "z", .command, editing: true), "Search preserves native text undo")
    assert(key(36, editing: true) && !model.choosingApp && model.grid.slots[0].app == finder,
           "Return assigns the highlighted result without applying the grid")
    model.choose(0); model.search = "missing-app"
    let beforeEmptySearch = model.grid
    assert(key(36, editing: true) && model.choosingApp && model.grid == beforeEmptySearch)
    assert(key(53, editing: true) && !model.hasActiveLayer && model.selectedCell == 0)
    assert(key(5, "g") && model.resizing)
    let beforeResize = model.grid
    assert(key(124) && model.draftColumns == 4 && model.grid == beforeResize)
    assert(key(53) && !model.resizing && model.grid == beforeResize, "Escape discards size preview")
    assert(key(5, "g") && model.resizing && key(5, "g") && !model.resizing && model.grid == beforeResize, "G toggles sizing off")
    assert(key(5, "g")); assert(key(125)); assert(key(36))
    assert(model.grid.rows == 3 && !model.resizing && !model.busy, "Return confirms size without opening windows")
    assert(key(6, "z", .command) && model.grid == beforeResize)
    assert(key(1, "s", .command) && model.saving)
    assert(!key(124, "", .shift, editing: true), "Saving preserves normal name editing")
    model.saveName = "Writing"; model.save()
    model.saveName = "Reading"; model.save()
    assert(key(31, "o", .command) && model.showingSaved)
    assert(key(125, editing: true) && model.selectedSavedGrid?.name == "Reading")
    model.savedSearch = "wri"
    assert(model.selectedSavedGrid?.name == "Writing", "Filtering resets the result highlight")
    assert(key(36, editing: true) && !model.hasActiveLayer && model.grid.slots.allSatisfy { $0.binding == nil })
    model.grid = DesktopGrid(slots: [GridSlot(app: safari, binding: live)])
    let beforeFill = model.grid
    model.repeatInEmptyCells(0)
    assert(model.grid.filledCount == 4 && model.grid.slots[0].binding == live)
    model.undo()
    assert(model.grid == beforeFill, "Repeat in empty cells is a single undo step")
    model.grid = DesktopGrid(columns: 1, rows: 1, slots: [GridSlot(app: safari, binding: live)])
    model.selectedCell = 0
    let beforeRemoval = model.grid
    assert(key(51))
    assert(model.grid.filledCount == 0 && model.grid.slots.count == 1 && model.grid.windowsToClose == [live],
           "Delete closes the exact last pane on Apply while leaving an empty cell")
    assert(key(6, "z", .command) && model.grid == beforeRemoval,
           "Undo must cancel the pending window closure")
    assert(key(117) && model.grid.windowsToClose == [live], "Forward Delete also queues window closure")
    model.undo()
    model.busy = true
    model.removePane(0)
    assert(model.grid == beforeRemoval, "Removing panes is blocked while applying")
    model.busy = false
    model.grid = .emptyDesktop
    model.removePane(0)
    assert(model.grid == .emptyDesktop, "Removing an empty cell must not queue a window closure")
    model.grid = DesktopGrid(columns: 2, rows: 2, slots: [GridSlot(app: safari, binding: live),
        GridSlot(app: finder, binding: other), GridSlot(app: safari, opensNewWindow: true)])
    let alreadyRemoved = GridWindowBinding(windowID: "removed", processSession: "session-c")
    model.grid.windowsToClose = [alreadyRemoved]
    let beforeCloseAll = model.grid
    assert(!key(51, "", [.command, .shift], editing: true) && model.grid == beforeCloseAll,
           "Text editing must never close panes")
    model.choose(0)
    assert(!key(51, "", [.command, .shift]) && model.grid == beforeCloseAll,
           "Close-all must not run inside the app chooser")
    model.closeLayers()
    assert(key(51, "", [.command, .shift]))
    assert(model.grid.slots.count == 1 && model.grid.filledCount == 0 && model.selectedCell == 0)
    assert(model.grid.windowsToClose == [alreadyRemoved, live, other],
           "Close-all queues each live window and preserves previously removed panes")
    assert(key(117, "", [.command, .shift]) && model.grid.windowsToClose == [alreadyRemoved, live, other],
           "Forward Delete works too and repeated close-all must not duplicate closures")
    assert(key(6, "z", .command) && model.grid == beforeCloseAll,
           "One undo restores all panes, new-window requests, and prior closures")
    model.busy = true
    assert(!key(51, "", [.command, .shift]) && model.grid == beforeCloseAll)
    model.removeAllPanes()
    assert(model.grid == beforeCloseAll, "Close-all is blocked while applying")
    model.busy = false
    model.grid = .emptyDesktop
    model.removeAllPanes()
    assert(model.grid == .emptyDesktop, "Close-all on an empty desktop is a no-op")
    model.grid = DesktopGrid(columns: 1, rows: 1, slots: [GridSlot(app: safari, binding: live)])
    let beforeReplace = model.grid
    model.choose(0); model.assign(finder)
    assert(model.grid.slots[0].app == finder && model.grid.slots[0].binding == nil
           && model.grid.windowsToClose == [live], "Replacing a pane's app closes its old window on Apply")
    model.choose(0); model.assign(safari)
    assert(model.grid.windowsToClose == [live], "Replacing an unbound pane queues nothing new")
    model.undo(); model.undo()
    assert(model.grid == beforeReplace, "Undo cancels the replacement's pending closure")
    model.grid = beforeFill
    model.busy = true
    model.selectedCell = 0
    assert(!key(124, "", .shift) && model.grid == beforeFill && model.selectedCell == 0)
    model.busy = false
    model.grid = DesktopGrid(columns: 2, rows: 1, slots: [GridSlot(app: safari, binding: live), GridSlot(app: finder, binding: other)])
    model.selectedCell = 0
    assert(key(124, "", [.command, .shift]))
    assert(model.selectedCell == 1 && model.grid.slots[1] == GridSlot(app: safari, opensNewWindow: true)
           && model.grid.windowsToClose == [other], "Copy replaces an occupied pane and closes its window on Apply")
    model.undo()
    assert(model.grid.slots[1].binding == other && model.grid.windowsToClose == nil, "Undo restores the replaced window")
    print("PASS: spatial keyboard navigation, exact-window swaps, copying into empty and occupied panes, search routing, size preview/cancel, saved search, atomic undo, and busy lock")
}

MainActor.assumeIsolated {
    let storage = GridMemoryDefaults(suiteName: nil)!
    let manager = WindowManager(preferences: Preferences(defaults: storage), backgroundArrangements: false)
    let model = GridEditorModel(manager: manager, defaults: storage)
    guard let display = Display.all.first else { return }
    let app = GridApp(bundleID: "pane.test", name: "Pane Test")
    let frames = Geometry.grid(count: 6, in: display.bounds, columns: 3, rows: 2, gap: 10)
    let panes = frames.enumerated().map { index, frame in
        (GridSlot(app: app, binding: GridWindowBinding(windowID: "window-\(index)", processSession: "session")), frame)
    }
    let live = DesktopGrid.desktop(panes: panes, in: display.bounds)
    model.begin(on: display, snapshot: live)
    assert(model.grid == live && model.originalGrid == live)
    model.split(0, toward: .right)
    assert(model.grid.slots.count == 7 && model.choosingApp && model.selectedCell == 6)
    model.assign(app)
    assert(model.grid.slots[6].opensNewWindow == true && model.grid.slots[6].binding == nil)
    model.undo(); model.undo()
    assert(model.grid == live, "Undo restores exact imported geometry")
    let divider = model.grid.dividers.first!
    let start = Date()
    for tick in 0..<60 { model.previewDivider(divider, position: divider.position + CGFloat(tick) * 0.0001) }
    model.finishDivider()
    let elapsed = Date().timeIntervalSince(start)
    assert(elapsed < 0.2, "Divider preview must stay local and responsive")
    model.undo()
    assert(model.grid == live, "An entire divider drag is one undo step")
    model.previewDivider(divider, position: divider.position + 0.1); model.finishDivider()
    model.resetDivider(model.grid.dividers.first { $0.id == divider.id }!)
    assert(zip(model.grid.normalizedFrames, live.normalizedFrames).allSatisfy { Geometry.approximatelyEqual($0, $1, tolerance: 0.0001) },
           "Double-click reset restores the even split")
    model.undo(); model.undo()
    assert(model.grid == live, "Reset is its own undo step")
    model.selectedCell = 3
    let mergeKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option, .shift], timestamp: 0,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 126)!
    assert(model.handleKey(mergeKey, editingText: false))
    assert(model.grid.slots.count == 5 && model.selectedCell == 2 && model.grid.windowsToClose == [panes[0].0.binding!],
           "Option–Shift–Arrow merges into the selected pane and closes the absorbed window on Apply")
    assert(model.grid.slots[2].binding == panes[3].0.binding)
    model.undo()
    assert(model.grid == live && model.grid.windowsToClose == nil)
    model.split(0, toward: .bottom); model.closeLayers()
    let beforeMismatch = model.grid
    model.merge(0, toward: .right)
    assert(model.grid == beforeMismatch && !model.message.isEmpty, "Panes that don't line up are left alone")
    model.undo()
    assert(model.grid == live)
    model.removePane(0)
    assert(model.grid.slots.count == 5 && model.grid.windowsToClose == [panes[0].0.binding!])
    assert(manager.windows.isEmpty, "Draft edits must not perform window operations")
    model.undo()
    assert(model.grid == live && model.grid.windowsToClose == nil)
    model.removePane(0)
    model.endEditing()
    model.begin(on: display, snapshot: live)
    assert(model.grid == live && model.grid.windowsToClose == nil, "Cancelling discards pending window closures")
    model.newGrid(); model.endEditing()
    model.begin(on: display, snapshot: live)
    assert(model.grid == live, "Reopening reads actual windows instead of the cancelled draft")
    model.begin(on: display, snapshot: .emptyDesktop)
    assert(model.grid.slots.count == 1 && model.grid.filledCount == 0, "An empty desktop never inherits another desktop's layout")
    model.endEditing()
    let captureStart = Date()
    model.begin(on: display)
    let captureElapsed = Date().timeIntervalSince(captureStart)
    assert(captureElapsed < 0.15, "Live desktop capture should not wait for AX discovery")
    model.endEditing()
    print(String(format: "PASS: live desktop replacement, split/new-window intent, divider undo/reset, keyboard merges, deferred removal/close, cancellation, empty desktop; 60 drag updates %.1f ms, live capture %.1f ms", elapsed * 1000, captureElapsed * 1000))
}
