import AppKit
import QuiltCore

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
