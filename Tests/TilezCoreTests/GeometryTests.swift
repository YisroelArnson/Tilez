import Foundation
import CoreGraphics
import TilezCore

final class GeometryTests {
    func testAutomaticGridsFitWithoutOverlapAcrossDisplayShapes() {
        for size in [CGSize(width: 1920, height: 1055), CGSize(width: 1080, height: 1895), CGSize(width: 6016, height: 3339)] {
            for count in 1...40 {
                let bounds = CGRect(origin: CGPoint(x: -1800, y: -800), size: size)
                let frames = Geometry.grid(count: count, in: bounds)
                expectEqual(frames.count, count)
                for (i, frame) in frames.enumerated() {
                    expect(bounds.contains(frame), "\(count) windows in \(size): \(frame)")
                    expectGreater(frame.width, 0)
                    expectGreater(frame.height, 0)
                    for other in frames.dropFirst(i + 1) {
                        expectFalse(frame.intersects(other), "Overlapping windows in grid with \(count) items")
                    }
                }
            }
        }
    }

    func testCustomGridExpandsRowsAndKeepsRequestedColumns() {
        let frames = Geometry.grid(count: 7, in: CGRect(x: 0, y: 0, width: 1200, height: 900), columns: 3, rows: 1, gap: 0)
        expectEqual(frames.count, 7)
        expectEqual(frames[0], CGRect(x: 0, y: 0, width: 400, height: 300))
        expectEqual(frames[6], CGRect(x: 0, y: 600, width: 400, height: 300))
    }

    func testRowsOnlyAndEmptyGrid() {
        let b = CGRect(x: 0, y: 0, width: 1200, height: 800)
        expectEqual(Geometry.grid(count: 0, in: b), [])
        let frames = Geometry.grid(count: 6, in: b, rows: 2, gap: 0)
        expectEqual(frames[5], CGRect(x: 800, y: 400, width: 400, height: 400))
    }

    func testHugeGapClampsWithoutInvalidFrames() {
        let frames = Geometry.grid(count: 100, in: CGRect(x: 0, y: 0, width: 200, height: 100), columns: 20, gap: 10000)
        expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 && $0.maxX <= 200 && $0.maxY <= 100 })
    }

    func testHalfSnapHasOneInteriorGapAndOuterMargins() {
        let b = CGRect(x: -1920, y: 45, width: 1920, height: 1000)
        let left = Geometry.placement(.left, in: b, current: .zero, gap: 12)
        let right = Geometry.placement(.right, in: b, current: .zero, gap: 12)
        expectEqual(right.minX - left.maxX, 12)
        expectEqual(left.minX - b.minX, 12)
        expectEqual(b.maxX - right.maxX, 12)
        expectEqual(left.width, right.width)
    }

    func testCycleAndQuarterCoordinates() {
        let b = CGRect(x: 100, y: -900, width: 1200, height: 900)
        expectEqual(Geometry.placement(.right, in: b, current: .zero, cycle: 1, gap: 0), CGRect(x: 900, y: -900, width: 400, height: 900))
        expectEqual(Geometry.placement(.left, in: b, current: .zero, cycle: 2, gap: 0).width, 800)
        expectEqual(Geometry.placement(.bottomRight, in: b, current: .zero, gap: 0), CGRect(x: 700, y: -450, width: 600, height: 450))
    }

    func testLayoutScalesToDifferentDisplayAndClampsOffscreenWindows() {
        let source = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let window = CGRect(x: -1440, y: 170, width: 960, height: 540)
        let normalized = Geometry.normalized(window, in: source)
        expectEqual(normalized, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let destination = CGRect(x: 0, y: 25, width: 1200, height: 800)
        expectEqual(Geometry.restored(normalized, in: destination), CGRect(x: 300, y: 225, width: 600, height: 400))
        let oversized = Geometry.restored(CGRect(x: -1, y: 2, width: 2, height: 2), in: destination)
        expectEqual(oversized, destination)
    }

    func testLayoutMatchingPreservesExactTitlesBeforeFallback() {
        let saved = [WindowIdentity(app: "codex", title: "Closed", ordinal: 0),
                     WindowIdentity(app: "codex", title: "Keep", ordinal: 1)]
        let live = [WindowIdentity(app: "codex", title: "Keep", ordinal: 0)]
        let matches = LayoutMatcher.match(saved: saved, live: live)
        expectEqual(matches[1], 0)
        expect(matches[0] == nil)
    }

    func testLayoutMatchingConsumesDuplicateTitlesOnceAndIsolatesApps() {
        let saved = [WindowIdentity(app: "codex", title: "New", ordinal: 0),
                     WindowIdentity(app: "codex", title: "New", ordinal: 1),
                     WindowIdentity(app: "editor", title: "New", ordinal: 0)]
        let live = [WindowIdentity(app: "editor", title: "New", ordinal: 0),
                    WindowIdentity(app: "codex", title: "New", ordinal: 0),
                    WindowIdentity(app: "codex", title: "Renamed", ordinal: 1)]
        let matches = LayoutMatcher.match(saved: saved, live: live)
        expectEqual(matches[0], 1)
        expectEqual(matches[1], 2)
        expectEqual(matches[2], 0)
        expectEqual(Set(matches.values).count, 3)
    }

    func testCenterFitsAnOversizedWindow() {
        let bounds = CGRect(x: 0, y: 30, width: 1000, height: 700)
        let result = Geometry.placement(.center, in: bounds, current: CGRect(x: -100, y: 0, width: 2000, height: 900), gap: 10)
        expectEqual(result, bounds.insetBy(dx: 10, dy: 10))
    }
}

private var assertionCount = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assertionCount += 1
    if !condition() { fatalError("Check failed: \(message)", file: file, line: line) }
}
private func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    expect(a == b, "\(a) != \(b)", file: file, line: line)
}
private func expectFalse(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    expect(!condition, message, file: file, line: line)
}
private func expectGreater<T: Comparable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    expect(a > b, "\(a) is not greater than \(b)", file: file, line: line)
}

@MainActor private func checkWindowCreation() async {
    do {
        var ids = ["a", "b"]
        var requested = 0
        var polls = 0
        var pending = false
        let result = try await WindowCount.prepare(target: 6, current: { ids }, requestNew: {
            expect(!pending, "Must wait before requesting another window")
            requested += 1; pending = true
        }, wait: {
            polls += 1
            if polls % 2 == 0 { ids.append("new-\(requested)"); pending = false }
        })
        expectEqual(requested, 4)
        expectEqual(result.count, 6)
        expectEqual(polls, 8)

        var unwantedRequests = 0
        let subset = try await WindowCount.prepare(target: 2, current: { ids }, requestNew: {
            unwantedRequests += 1
        }, wait: { fatalError("Existing windows should not need a wait") })
        expectEqual(subset, ["a", "b"])
        expectEqual(unwantedRequests, 0)

        var firstWindow: [String] = []
        let first = try await WindowCount.prepare(target: 1, current: { firstWindow }, requestNew: {
            firstWindow = ["first"]
        }, wait: {})
        expectEqual(first, ["first"])
    } catch { fatalError("Unexpected window creation error: \(error)") }

    var requests = 0
    do {
        _ = try await WindowCount.prepare(target: 6, current: { ["existing"] }, requestNew: { requests += 1 }, wait: {}, pollsPerWindow: 3)
        fatalError("An app that does not open a window must time out")
    } catch { expectEqual(error as? WindowCountError, .windowDidNotAppear) }
    expectEqual(requests, 1, file: #file, line: #line)

    do {
        _ = try await WindowCount.prepare(target: 0, current: { [] }, requestNew: { fatalError("Invalid count must not create windows") }, wait: {})
        fatalError("Invalid count accepted")
    } catch { expectEqual(error as? WindowCountError, .invalidTarget) }

    do {
        _ = try await WindowCount.prepare(target: 6, current: { [] }, requestNew: {}, wait: { throw CancellationError() })
        fatalError("Cancelled work continued")
    } catch { expect(error is CancellationError) }

    var generation = 0
    do {
        _ = try await WindowCount.prepare(target: 2, current: { ["window-\(generation)"] }, requestNew: { generation += 1 }, wait: {})
        fatalError("Repeatedly closing windows must not cause an endless loop")
    } catch { expectEqual(error as? WindowCountError, .windowsKeepClosing) }
    expectEqual(generation, 2)

    struct MenuUnavailable: Error {}
    var waits = 0
    do {
        _ = try await WindowCount.prepare(target: 1, current: { [] }, requestNew: { throw MenuUnavailable() }, wait: { waits += 1 })
        fatalError("Unavailable menu action must stop the request")
    } catch { expect(error is MenuUnavailable) }
    expectEqual(waits, 0)
}

private func checkSavedSetups() {
    let setup = WindowSetup(name: "Six chats", bundleID: "com.example.chat", appName: "Chat",
                            count: 6, columns: 3, rows: 2, gap: 12, displayID: "display-A", desktop: "display-A|space-UUID", freshWindows: true)
    expect(setup.isValid)
    do {
        let data = try JSONEncoder().encode(setup)
        let restored = try JSONDecoder().decode(WindowSetup.self, from: data)
        expectEqual(restored, setup)
        expectEqual(restored.desktop, "display-A|space-UUID")
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "preserveFullScreen")
        let migrated = try JSONDecoder().decode(WindowSetup.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(!migrated.keepsFullScreen, "Existing saved setups must still load")
        var preserve = setup; preserve.preserveFullScreen = true
        let kept = try JSONDecoder().decode(WindowSetup.self, from: JSONEncoder().encode(preserve))
        expect(kept.keepsFullScreen)
    } catch { fatalError("Setup persistence failed: \(error)") }
    var invalid = setup
    invalid.count = 0; expect(!invalid.isValid)
    invalid = setup; invalid.gap = .infinity; expect(!invalid.isValid)
    invalid = setup; invalid.bundleID = ""; expect(!invalid.isValid)

    let initial: Set<String> = ["other-desktop-1", "other-desktop-2", "destination-1"]
    let live = ["other-desktop-1", "destination-1", "new-window", "other-desktop-2"]
    let reuse = WindowSetup.eligibleIDs(live: live, initial: initial, onDestination: ["destination-1"], fresh: false)
    expectEqual(reuse, ["destination-1", "new-window"])
    let fresh = WindowSetup.eligibleIDs(live: live, initial: initial, onDestination: ["destination-1"], fresh: true)
    expectEqual(fresh, ["new-window"])
}

@MainActor private func checkWindowDiscovery() async {
    // Same inventory decision used by Accessibility.windows() and the creation loop.
    expect(WindowAvailability(fullScreen: true).listed, "An open full-screen window must appear in the app's window list")
    expect(WindowAvailability(minimized: true).listed, "Minimized windows must remain discoverable")
    expect(WindowAvailability(hidden: true).listed, "Hidden apps must retain their window count")
    expect(WindowAvailability(resizable: false).listed, "Fixed-size windows must be visible even when they cannot fill a tile")
    expect(!WindowAvailability(fullScreen: true).automatic, "Watch must leave full-screen windows alone")
    expect(!WindowAvailability(hidden: true).automatic, "Watch must not unhide apps")
    expect(!WindowAvailability(minimized: true).automatic, "Watch must not restore minimized windows")
    expect(!WindowAvailability(resizable: false).automatic)
    expect(!WindowAvailability(document: false).listed, "Dialogs are not independent document windows")
    expect(WindowAvailability(fullScreen: true).needsFullScreenExit(preserve: false))
    expect(!WindowAvailability(fullScreen: true).needsFullScreenExit(preserve: true))
    expect(!WindowAvailability(accessible: false).automatic, "Watch must not pull windows from other desktops")
    expect(!WindowInventory.shouldExclude(isDocument: nil, modal: nil), "Off-Space AX metadata can be temporarily unavailable")
    expect(!WindowInventory.shouldExclude(isDocument: true, modal: false))
    expect(WindowInventory.shouldExclude(isDocument: false, modal: false), "Do not count full-screen toolbars or dialogs")
    expect(WindowInventory.shouldExclude(isDocument: nil, modal: true))
    expect(!WindowInventory.shouldExclude(isDocument: false, modal: false, minimized: true), "macOS can label minimized document windows AXDialog")
    expect(WindowInventory.shouldExclude(isDocument: false, modal: true, minimized: true), "A modal dialog remains excluded")
    struct Record: Identifiable { let id: Int; var accessible = false }
    var server = [Record(id: 1)]
    var visible = [Record(id: 1, accessible: true)]
    var opened = 0
    do {
        let result = try await WindowCount.prepare(target: 3, current: {
            WindowInventory.merge(accessible: visible, otherDesktops: server).map { String($0.id) }
        }, requestNew: {
            opened += 1
            // Opening a full-screen Space makes AXWindows omit the previous windows.
            let next = Record(id: server.count + 1, accessible: true)
            server.append(next); visible = [next]
        }, wait: {})
        expectEqual(result.count, 3)
        expectEqual(opened, 2, file: #file, line: #line)
        expectEqual(Set(result), ["1", "2", "3"])
        let merged = WindowInventory.merge(accessible: visible, otherDesktops: server)
        expectEqual(merged.count, 3)
        expect(merged.first!.accessible, "An available AX element takes precedence over its placeholder")
    } catch { fatalError("Other-desktop inventory caused duplicate opens: \(error)") }
    var inventory: [(String, WindowAvailability)] = []
    var requests = 0
    do {
        let ids = try await WindowCount.prepare(target: 3, current: {
            inventory.filter { $0.1.listed }.map { $0.0 }
        }, requestNew: {
            requests += 1
            inventory.append(("full-screen-\(requests)", WindowAvailability(fullScreen: true)))
        }, wait: {}, pollsPerWindow: 2)
        expectEqual(ids.count, 3)
        expectEqual(requests, 3)
    } catch { fatalError("New full-screen windows disappeared from the creation loop: \(error)") }
}

private func checkActiveLayouts() {
    let setup = WindowSetup(name: "Eight", bundleID: "test", appName: "Test", count: 8)
    let first = ActiveLayout(processSession: "launch-1", windowIDs: (1...8).map { "w\($0)" }, setup: setup)
    let second = ActiveLayout(processSession: "launch-1", windowIDs: (9...16).map { "w\($0)" }, setup: setup)
    let all = Set(first.windowIDs + second.windowIDs)
    // Shrinking and closing must be restricted to the requested set, including identical titles/apps.
    let closing = ActiveLayouts.closing(members: first.windowIDs, keeping: Set(first.windowIDs.prefix(6)))
    expectEqual(closing, ["w7", "w8"])
    expect(Set(closing).isDisjoint(with: Set(second.windowIDs)))
    expectEqual(ActiveLayouts.closing(members: first.windowIDs, keeping: []), first.windowIDs)
    // Growing on the same desktop must open new windows, not borrow another set's existing windows.
    expectEqual(ActiveLayouts.eligible(live: Array(all).sorted() + ["new1", "new2"], initial: all, members: Set(first.windowIDs)).count, 10)
    expectEqual(ActiveLayouts.eligible(live: second.windowIDs, initial: all, members: Set(first.windowIDs)), [])
    // Closed windows disappear, and a restarted process cannot inherit destructive targets.
    let remaining = ActiveLayouts.reconcile([first, second], live: ["launch-1": all.subtracting(["w7", "w8"])])
    expectEqual(remaining[0].windowIDs.count, 6)
    expectEqual(remaining[1].windowIDs, second.windowIDs)
    expectEqual(ActiveLayouts.reconcile([first], live: ["launch-2": Set(first.windowIDs)]), [])
    // Reassigning windows transfers ownership without creating duplicate close targets.
    let moved = ActiveLayout(processSession: "launch-1", windowIDs: ["w1", "w2"], setup: setup)
    let recorded = ActiveLayouts.recording(moved, in: [first, second])
    expectEqual(recorded[0].windowIDs, Array(first.windowIDs.dropFirst(2)))
    expectEqual(Set(recorded.flatMap(\.windowIDs)).count, recorded.flatMap(\.windowIDs).count)
    var updated = first
    updated.windowIDs = Array(first.windowIDs.prefix(6))
    expectEqual(ActiveLayouts.recording(updated, in: [first, second]).map(\.id), [first.id, second.id])
    // Persistence preserves session, order, settings, and identity across Tilez restarts.
    let roundTrip = try! JSONDecoder().decode([ActiveLayout].self, from: JSONEncoder().encode([first, second]))
    expectEqual(roundTrip, [first, second])
    expectEqual(ActiveLayouts.reconcile(roundTrip, live: ["launch-1": all]), [first, second])
}

private func checkMenuPanelGeometry() {
    // Includes the user's vertically offset display and a smaller display below/left of the origin.
    for visible in [CGRect(x: 822, y: 1243, width: 3008, height: 1662),
                    CGRect(x: -1280, y: -800, width: 1280, height: 690),
                    CGRect(x: 0, y: 0, width: 1024, height: 500)] {
        for arranging in [false, true] {
            for count in [0, 2, 30] {
                let size = MenuPanelGeometry.contentSize(arranging: arranging, setupCount: count, needsPermission: true, visibleFrame: visible)
                let panelSize = CGSize(width: size.width + 26, height: size.height + 26)
                for x in [visible.minX, visible.midX, visible.maxX - 22] {
                    let anchor = CGRect(x: x, y: visible.maxY + 1.5, width: 22, height: 27)
                    let frame = CGRect(origin: MenuPanelGeometry.origin(panelSize: panelSize, anchor: anchor, visibleFrame: visible), size: panelSize)
                    expect(visible.contains(frame), "Off-screen menu panel: \(frame) in \(visible)")
                    expect(frame.maxY <= anchor.minY, "Panel covers the menu bar")
                }
            }
        }
        let compact = MenuPanelGeometry.contentSize(arranging: false, setupCount: 2, needsPermission: false, visibleFrame: visible)
        let expanded = MenuPanelGeometry.contentSize(arranging: true, setupCount: 2, needsPermission: false, visibleFrame: visible)
        expect(compact.height < expanded.height, "Two saved setups should not reserve a full-height picker")
    }
}

@main struct CheckRunner {
    @MainActor static func main() async {
        checkWindowMenus()
        await checkWindowDiscovery()
        let tests = GeometryTests()
        tests.testAutomaticGridsFitWithoutOverlapAcrossDisplayShapes()
        tests.testCustomGridExpandsRowsAndKeepsRequestedColumns()
        tests.testRowsOnlyAndEmptyGrid()
        tests.testHugeGapClampsWithoutInvalidFrames()
        tests.testHalfSnapHasOneInteriorGapAndOuterMargins()
        tests.testCycleAndQuarterCoordinates()
        tests.testLayoutScalesToDifferentDisplayAndClampsOffscreenWindows()
        tests.testCenterFitsAnOversizedWindow()
        tests.testLayoutMatchingPreservesExactTitlesBeforeFallback()
        tests.testLayoutMatchingConsumesDuplicateTitlesOnceAndIsolatesApps()
        await checkWindowCreation()
        await checkWindowSettling()
        checkDesktopGrids()
        checkPaneLayouts()
        checkSavedSetups()
        checkActiveLayouts()
        checkWorkspaces()
        checkMenuPanelGeometry()
        print("PASS: 32 geometry, matching, creation, visibility, saved-setup, active-layout, workspace, and menu-panel scenarios, \(assertionCount) assertions.")
    }
}

func checkDesktopGrids() {
    let safari = GridApp(bundleID: "com.apple.Safari", name: "Safari")
    let notes = GridApp(bundleID: "com.apple.Notes", name: "Notes")
    let bound = GridWindowBinding(windowID: "123:window-1", processSession: "123|launch")
    var grid = DesktopGrid(slots: [GridSlot(app: safari, binding: bound), GridSlot(app: notes)])
    expect(grid.isValid && grid.slots.count == 4, "New grids include empty cells")
    grid.move(from: 0, to: 2, repeating: true)
    expect(grid.slots[2].app == safari && grid.slots[2].binding == nil, "Repeating creates an unbound app, not a duplicate window identity")
    expect(grid.slots[0].binding == bound, "Repeating preserves the original window")
    grid.move(from: 0, to: 1, repeating: false)
    expect(grid.slots[0].app == notes && grid.slots[1].binding == bound, "Swap follows exact windows")
    grid.resize(columns: 3, rows: 2)
    expect(grid.slots[3].app == safari && grid.slots[2].app == nil, "Resizing preserves row and column positions")
    expect(grid.slots.count == 6 && grid.isValid, "Dimensions and cell count agree")
    let template = grid.template
    expect(template.slots.allSatisfy { $0.binding == nil }, "Saved grids contain apps, never live window IDs")
    expect(template.slots.map(\.app) == grid.slots.map(\.app), "Saving preserves app choices and holes")
    let data = try! JSONEncoder().encode(grid)
    expect((try! JSONDecoder().decode(DesktopGrid.self, from: data)) == grid, "Desktop sessions survive restart")
    grid.resize(columns: 1, rows: 1)
    expect(grid.slots.count == 1 && grid.slots[0].app == notes, "Shrinking removes assignments without closing windows")
    var full = DesktopGrid(columns: 2, rows: 2, slots: Array(repeating: GridSlot(app: safari), count: 4))
    let newIndex = full.makeRoom()
    expect(full.columns == 3 && full.rows == 2 && newIndex == 2, "Adding to full grid expands without replacing an app")
    expect(full.slots[3].app == safari, "Auto expansion preserves second row")
    full = DesktopGrid(columns: 6, rows: 4, slots: Array(repeating: GridSlot(app: safari), count: 24))
    expect(full.makeRoom() == nil && full.slots.count == 24, "Full maximum grid refuses overflow")
    var invalid = full
    invalid.slots = []
    expect(!invalid.isValid, "Malformed persisted cell count is rejected")
    full.move(from: -1, to: 99, repeating: true)
    expect(full.isValid, "Invalid drag indices are ignored")
    let bounds = CGRect(x: -1800, y: -400, width: 1800, height: 1000)
    let frames = Geometry.grid(count: template.slots.count, in: bounds, columns: template.columns, rows: template.rows, gap: 10)
    expect(frames.count == 6 && frames[3].minY > frames[0].minY, "Empty cells reserve real desktop geometry")
    print("PASS: desktop-grid sizing, repetition, exact-window swaps, persistence, empty cells, overflow, and malformed state")
}

func checkPaneLayouts() {
    let bounds = CGRect(x: -1800, y: -400, width: 1800, height: 1000)
    let app = GridApp(bundleID: "chat.test", name: "Chat")
    func slot(_ index: Int) -> GridSlot {
        GridSlot(app: app, binding: GridWindowBinding(windowID: "w\(index)", processSession: "session"))
    }
    expectEqual(DesktopGrid.desktop(panes: [], in: bounds), .emptyDesktop)
    let single = DesktopGrid.desktop(panes: [(slot(0), bounds)], in: bounds)
    expectEqual(single.slots.count, 1)
    expectEqual(single.frames(in: bounds), [bounds])
    let sixFrames = Geometry.grid(count: 6, in: bounds, columns: 3, rows: 2, gap: 10)
    let six = DesktopGrid.desktop(panes: sixFrames.enumerated().map { (slot($0.offset), $0.element) }, in: bounds)
    expectEqual(six.slots.count, 6)
    for (actual, expected) in zip(six.frames(in: bounds), sixFrames) { expect(Geometry.approximatelyEqual(actual, expected, tolerance: 0.001)) }
    let unequalFrames = [CGRect(x: -1800, y: -400, width: 600, height: 1000), CGRect(x: -1190, y: -400, width: 1190, height: 1000)]
    let unequal = DesktopGrid.desktop(panes: unequalFrames.enumerated().map { (slot($0.offset), $0.element) }, in: bounds)
    for (actual, expected) in zip(unequal.frames(in: bounds), unequalFrames) { expect(Geometry.approximatelyEqual(actual, expected, tolerance: 0.001)) }
    let overlapping = DesktopGrid.desktop(panes: [(slot(0), bounds), (slot(1), CGRect(x: -1500, y: -300, width: 700, height: 700))], in: bounds)
    expectEqual(overlapping.slots.count, 2)
    expect(overlapping.normalizedFrames[0].contains(overlapping.normalizedFrames[1]), "Overlaps are represented instead of silently rearranged")
    for edge in PaneEdge.allCases {
        var layout = single
        let added = layout.split(0, toward: edge)!
        expectEqual(added, 1)
        expectEqual(layout.slots[0].binding, slot(0).binding)
        expect(layout.slots[1].app == nil && layout.isValid)
        let divider = layout.dividers.first!
        layout.resizeDivider(divider, to: 0.7)
        expect(layout.isValid)
        expect(abs(layout.dividers.first!.position - 0.7) < 0.001)
        layout.resizeDivider(layout.dividers.first!, to: 99)
        expect(layout.isValid && layout.normalizedFrames.allSatisfy { $0.width >= 0.039 && $0.height >= 0.039 }, "Dragging past bounds clamps the pane size")
        layout.removePane(1)
        expectEqual(layout.slots, single.slots)
        expect(Geometry.approximatelyEqual(layout.normalizedFrames[0], single.normalizedFrames[0], tolerance: 0.001))
    }
    var junction = single
    _ = junction.split(0, toward: .right)
    _ = junction.split(1, toward: .bottom)
    junction.slots[1] = slot(1); junction.slots[2] = slot(2)
    let vertical = junction.dividers.first { $0.vertical }!
    junction.resizeDivider(vertical, to: 0.6)
    expect(abs(junction.normalizedFrames[1].minX - junction.normalizedFrames[2].minX) < 0.001, "T junctions resize both adjacent panes")
    expect(junction.isValid)
    let beforeSwap = junction.normalizedFrames
    junction.move(from: 0, to: 2, repeating: false)
    expectEqual(junction.normalizedFrames, beforeSwap)
    expectEqual(junction.slots[2].binding, slot(0).binding)
    junction.removePane(0)
    expectEqual(junction.slots.count, 2)
    expect(junction.normalizedFrames.allSatisfy { abs($0.width - 1) < 0.001 }, "Removing a large pane expands its stacked neighbors")
    expect(junction.template.slots.allSatisfy { $0.binding == nil })
    expectEqual(junction.template.normalizedFrames, junction.normalizedFrames)
    let decoded = try! JSONDecoder().decode(DesktopGrid.self, from: JSONEncoder().encode(junction))
    expectEqual(decoded, junction)
    let old = Data(#"{"columns":1,"rows":1,"slots":[{"app":{"bundleID":"chat.test","name":"Chat"}}]}"#.utf8)
    expect((try! JSONDecoder().decode(DesktopGrid.self, from: old)).isValid, "Existing templates decode without new fields")
    var requests = single
    _ = requests.split(0, toward: .right)
    requests.slots[1] = GridSlot(app: app, opensNewWindow: true)
    expectEqual(requests.candidateIDs(bundleID: app.bundleID, session: "session", available: ["unrelated", "w0", "new"], initial: ["unrelated", "w0"]), ["w0", "new"])
    expectEqual(requests.candidateIDs(bundleID: app.bundleID, session: "restarted", available: ["w0"], initial: ["w0"]), [])
    let covered = DesktopGrid.visibleDesktop(panes: [(slot(0), bounds), (slot(1), bounds)], in: bounds)
    expectEqual(covered.slots.count, 1)
    expectEqual(covered.slots[0].binding, slot(0).binding)
    let halves = [CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height),
                  CGRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)]
    let unionCovered = DesktopGrid.visibleDesktop(panes: [(slot(0), halves[0]), (slot(1), halves[1]), (slot(2), bounds)], in: bounds)
    expect(unionCovered.slots.count == 2, "Occlusion uses the union of front windows")
    let partial = DesktopGrid.visibleDesktop(panes: [(slot(0), halves[0]), (slot(1), bounds)], in: bounds)
    expect(partial.slots.count == 2, "Partially visible windows preserve their full geometry")
    let eightFrames = Geometry.grid(count: 8, in: bounds, columns: 4, rows: 2, gap: 10)
    var eight = DesktopGrid.desktop(panes: eightFrames.enumerated().map { (slot($0.offset), $0.element) }, in: bounds)
    expectEqual(eight.mergeCandidates(7, toward: .top), [3])
    expectEqual(eight.merge(7, toward: .top), 6)
    expect(eight.isValid && eight.slots.count == 7 && eight.slots[6].binding == slot(7).binding)
    expect(abs(eight.normalizedFrames[6].minY - eight.normalizedFrames[0].minY) < 0.001
           && abs(eight.normalizedFrames[6].maxY - eight.normalizedFrames[4].maxY) < 0.001, "Merging a column spans its full height")
    expect(eight.mergeCandidates(2, toward: .right).isEmpty, "A short pane can't absorb a taller neighbor")
    var stacked = single
    _ = stacked.split(0, toward: .right)
    _ = stacked.split(1, toward: .bottom)
    expect(stacked.mergeCandidates(1, toward: .left).isEmpty)
    stacked.slots[0] = GridSlot()
    stacked.slots[2] = slot(2)
    expectEqual(Set(stacked.mergeCandidates(0, toward: .right)), [1, 2])
    expectEqual(stacked.merge(0, toward: .right), 0)
    expect(stacked.slots == [slot(2)] && abs(stacked.normalizedFrames[0].width - 1) < 0.001, "An empty pane takes an absorbed app")
    var halves2 = single
    _ = halves2.split(0, toward: .right)
    let even = halves2.normalizedFrames
    halves2.resizeDivider(halves2.dividers[0], to: 0.8)
    halves2.resetDivider(halves2.dividers[0])
    expect(zip(halves2.normalizedFrames, even).allSatisfy { Geometry.approximatelyEqual($0, $1, tolerance: 0.0001) }, "Reset restores an even split")
    var threeColumns = DesktopGrid.desktop(panes: Geometry.grid(count: 6, in: bounds, columns: 3, rows: 2, gap: 10).enumerated()
        .map { (slot($0.offset), $0.element) }, in: bounds)
    let columnsBefore = threeColumns.normalizedFrames
    let junctionDivider = threeColumns.dividers.first { $0.vertical && $0.before == 0 }!
    threeColumns.resizeDivider(junctionDivider, to: 0.2)
    threeColumns.resetDivider(threeColumns.dividers.first { $0.vertical && $0.before == 0 }!)
    expect(zip(threeColumns.normalizedFrames, columnsBefore).allSatisfy { Geometry.approximatelyEqual($0, $1, tolerance: 0.0001) },
           "Reset moves every pane sharing the boundary")
    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0005 }
    var free = single
    free.resizePane(0, edges: [.right], by: CGSize(width: -0.3, height: 0))
    expect(near(free.normalizedFrames[0].maxX, 0.7) && near(free.normalizedFrames[0].minX, 0) && free.isValid,
           "A free side moves alone")
    var cornered = single
    cornered.resizePane(0, edges: [.left, .top], by: CGSize(width: 0.2, height: 0.1))
    let corner = cornered.normalizedFrames[0]
    expect(near(corner.minX, 0.2) && near(corner.minY, 0.1) && near(corner.maxX, 1) && near(corner.maxY, 1),
           "A corner resizes both directions")
    var clamped = single
    clamped.resizePane(0, edges: [.right, .bottom], by: CGSize(width: 5, height: 5))
    expect(clamped.normalizedFrames[0] == single.normalizedFrames[0], "Free sides stop at the screen edge")
    clamped.resizePane(0, edges: [.right], by: CGSize(width: -5, height: 0))
    expect(clamped.normalizedFrames[0].width >= 0.039 && clamped.isValid, "Panes keep a minimum size")
    var shared = single
    _ = shared.split(0, toward: .right)
    let sharedBefore = shared.normalizedFrames
    shared.resizePane(0, edges: [.right], by: CGSize(width: 0.1, height: 0))
    expect(near(shared.normalizedFrames[0].maxX, sharedBefore[0].maxX + 0.1)
           && near(shared.normalizedFrames[1].minX, sharedBefore[1].minX + 0.1)
           && near(shared.normalizedFrames[1].maxX, 1), "A shared side moves the neighbor's side with it")
    var quad = DesktopGrid.desktop(panes: Geometry.grid(count: 4, in: bounds, columns: 2, rows: 2, gap: 10).enumerated()
        .map { (slot($0.offset), $0.element) }, in: bounds)
    let quadBefore = quad.normalizedFrames
    quad.resizePane(0, edges: [.right, .bottom], by: CGSize(width: 0.1, height: 0.1))
    let quadAfter = quad.normalizedFrames
    expect(near(quadAfter[0].maxX, quadBefore[0].maxX + 0.1) && near(quadAfter[0].maxY, quadBefore[0].maxY + 0.1)
           && near(quadAfter[1].minX, quadBefore[1].minX + 0.1) && near(quadAfter[2].minY, quadBefore[2].minY + 0.1)
           && near(quadAfter[3].minX, quadBefore[3].minX + 0.1) && near(quadAfter[3].minY, quadBefore[3].minY + 0.1)
           && quad.isValid, "A four-way corner moves both dividers")
    for i in quadAfter.indices { for j in quadAfter.indices where j > i {
        expect(!quadAfter[i].insetBy(dx: 0.001, dy: 0.001).intersects(quadAfter[j]), "Corner drags never overlap panes \(i) and \(j)")
    } }
    var row = quad
    row.resizePane(0, edges: [.right], by: CGSize(width: 0.1, height: 0))
    expect(near(row.normalizedFrames[2].maxX, quadAfter[2].maxX) && near(row.normalizedFrames[0].maxX, quadAfter[0].maxX + 0.1), "A side drag leaves the other row's divider alone")
    var gapped = DesktopGrid(panes: [slot(0), slot(1)], frames: [CGRect(x: 0, y: 0, width: 0.3, height: 1),
                                                                   CGRect(x: 0.6, y: 0, width: 0.4, height: 1)])
    expect(gapped.dividers.isEmpty)
    gapped.resizePane(0, edges: [.right], by: CGSize(width: 0.5, height: 0))
    expect(near(gapped.normalizedFrames[0].maxX, 0.592) && near(gapped.normalizedFrames[1].minX, 0.6),
           "A free side stops just short of the pane it would cover")
    expectEqual(gapped.dividers.count, 1)
    // Drifted windows, like a captured desktop: three columns, the left one split.
    var drifted = DesktopGrid(panes: (0..<4).map(slot), frames: [
        CGRect(x: 0, y: 0, width: 0.327, height: 0.515), CGRect(x: 0.004, y: 0.505, width: 0.327, height: 0.495),
        CGRect(x: 0.337, y: 0.023, width: 0.335, height: 0.967), CGRect(x: 0.673, y: 0.004, width: 0.325, height: 0.993)])
    expect(drifted.mergeCandidates(0, toward: .bottom).isEmpty, "Overlapping, offset panes don't line up before realigning")
    expect(drifted.realign())
    let third = CGFloat(1) / 3, g: CGFloat = 0.004
    let tidy = [CGRect(x: 0, y: 0, width: third - g, height: 0.5 - g), CGRect(x: 0, y: 0.5 + g, width: third - g, height: 0.5 - g),
                CGRect(x: third + g, y: 0, width: third - 2 * g, height: 1), CGRect(x: 2 * third + g, y: 0, width: third - g, height: 1)]
    expect(zip(drifted.normalizedFrames, tidy).allSatisfy { Geometry.approximatelyEqual($0, $1, tolerance: 0.0001) },
           "Realign snaps edges to shared lines, even thirds and halves, and the screen: \(drifted.normalizedFrames)")
    expectEqual(drifted.mergeCandidates(0, toward: .bottom), [1])
    let realigned = drifted
    drifted.realign()
    expectEqual(drifted, realigned)
    var holed = DesktopGrid(panes: [slot(0), slot(1)], frames: [CGRect(x: 0, y: 0, width: 0.3, height: 1), CGRect(x: 0.5, y: 0.01, width: 0.49, height: 0.98)])
    holed.realign()
    expect(near(holed.normalizedFrames[0].maxX, 0.3) && near(holed.normalizedFrames[1].minX, 0.5)
           && holed.normalizedFrames[1] == CGRect(x: 0.5, y: 0, width: 0.5, height: 1), "Realign keeps a wide hole and reaches the screen edges")
    var legacy = DesktopGrid(columns: 2, rows: 2)
    legacy.realign()
    expectEqual(legacy, DesktopGrid(columns: 2, rows: 2))
    let start = Date()
    var edit = six
    for index in 0..<500 {
        let divider = edit.dividers[index % edit.dividers.count]
        edit.resizeDivider(divider, to: divider.position + (index.isMultiple(of: 2) ? 0.001 : -0.001))
    }
    let elapsed = Date().timeIntervalSince(start)
    expect(elapsed < 1, "500 divider updates should fit within one second; got \(elapsed)")
    print(String(format: "PASS: live pane geometry, empty/full/six-window desktops, unequal and overlapping windows, split/remove/T-junction resizing, edge and corner resizing, column merges, divider reset, realign, exact bindings, legacy templates, new-window isolation; 500 divider edits %.1f ms", elapsed * 1000))
}

@MainActor private func checkWindowSettling() async {
    do {
        var waits = 0
        let ready: [String] = try await WindowSettling.finish(pending: { [] }, retry: { _ in fatalError("Ready windows must not be resized") }, wait: { waits += 1 })
        expect(ready.isEmpty && waits == 0, "Already-settled windows finish without delay")
        var retries = 0
        let delayed = try await WindowSettling.finish(pending: { retries < 3 ? ["opening-window"] : [] }, retry: { _ in retries += 1 }, wait: { waits += 1 })
        expect(delayed.isEmpty && retries == 3, "A window that ignores initial resizing during its opening transition is retried automatically")
        waits = 0; retries = 0
        let constrained = try await WindowSettling.finish(pending: { ["minimum-size"] }, retry: { _ in retries += 1 }, wait: { waits += 1 })
        expect(constrained == ["minimum-size"] && waits == 16 && retries == 4, "Minimum-size failures stop after a bounded number of retries")
        do {
            _ = try await WindowSettling.finish(pending: { ["window"] }, retry: { _ in fatalError("Cancellation must stop retries") }, wait: { throw CancellationError() })
            expect(false, "Cancellation must propagate")
        } catch is CancellationError {} catch { expect(false, "Unexpected error") }
        print("PASS: zero-delay settled placements, delayed opening transitions, bounded constraints, and cancellation")
    } catch { fatalError("Unexpected settling failure: \(error)") }
}

func checkWorkspaces() {
    let app = GridApp(bundleID: "chat.test", name: "Chat")
    func binding(_ index: Int) -> GridWindowBinding { GridWindowBinding(windowID: "1:window-\(index)", processSession: "1|launch") }
    func pane(_ index: Int) -> GridSlot { GridSlot(app: app, binding: binding(index)) }
    let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
    let topRight = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
    let bottomRight = CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
    let three = DesktopGrid(panes: [pane(0), pane(1), pane(2)], frames: [left, topRight, bottomRight])

    // Saving keeps only real windows; empty panes and new-window placeholders never join.
    let withHole = DesktopGrid(panes: [pane(0), GridSlot(), GridSlot(app: app, opensNewWindow: true)], frames: [left, topRight, bottomRight])
    let saved = Workspace(name: "Coding", screens: [WorkspaceScreen(displayID: "A", arranging: withHole)!])
    expectEqual(saved.windowCount, 1)
    expect(WorkspaceScreen(displayID: "A", arranging: .emptyDesktop) == nil, "A screen with no windows isn't part of a workspace")
    let data = try! JSONEncoder().encode(saved)
    expectEqual(try! JSONDecoder().decode(Workspace.self, from: data), saved)

    // A closed window leaves for good, and its neighbor grows into the space.
    let workspace = Workspace(name: "Coding", screens: [WorkspaceScreen(displayID: "A", arranging: three)!])
    let closedOne = workspace.keeping { $0 != binding(2) }!
    expectEqual(closedOne.windowCount, 2)
    let grown = closedOne.screens[0].grid.normalizedFrames
    expect(Geometry.approximatelyEqual(grown[1], CGRect(x: 0.5, y: 0, width: 0.5, height: 1), tolerance: 0.001), "The pane above grows into the closed window's space")
    expect(workspace.keeping { _ in false } == nil, "A workspace ends when its last window closes")
    expectEqual(workspace.keeping { _ in true }, workspace)

    // One screen follows you; several screens return to their own displays.
    expectEqual(workspace.destinations(connected: ["A", "B"], current: "B").map(\.displayID), ["B"])
    let spanning = Workspace(name: "Everything", screens: [WorkspaceScreen(displayID: "A", arranging: three)!,
        WorkspaceScreen(displayID: "B", arranging: DesktopGrid(panes: [pane(3)], frames: [CGRect(x: 0, y: 0, width: 1, height: 1)]))!])
    expectEqual(spanning.destinations(connected: ["A", "B"], current: "A").map(\.displayID), ["A", "B"])
    expect(spanning.destinations(connected: ["B"], current: "B").map(\.displayID) == ["B"], "A disconnected screen's windows stay put")
    let spanningClosed = spanning.keeping { $0 != binding(3) }!
    expect(spanningClosed.screens.map(\.displayID) == ["A"], "A screen whose windows all closed leaves the workspace")

    // Modified: moved, missing, or extra windows; exact placement within tolerance isn't.
    expectFalse(workspace.isModified(on: "Z", showing: three), "A one-screen workspace compares against any screen showing it")
    var nudged = three
    nudged.resizeDivider(nudged.dividers.first { $0.vertical }!, to: 0.505)
    expectFalse(workspace.isModified(on: "A", showing: nudged))
    nudged.resizeDivider(nudged.dividers.first { $0.vertical }!, to: 0.6)
    expect(workspace.isModified(on: "A", showing: nudged), "Moved windows make it modified")
    var missing = three
    missing.removePane(2)
    expect(workspace.isModified(on: "A", showing: missing), "A window pulled away makes it modified")
    let extra = DesktopGrid(panes: [pane(0), pane(1), pane(2), pane(9)], frames: [left, topRight, bottomRight, left])
    expect(workspace.isModified(on: "A", showing: extra), "Saving would add the extra window")
    expect(spanning.isModified(on: "C", showing: three), "A screen outside a multi-screen workspace never matches it")

    // Saving replaces that screen and keeps the others.
    let resaved = spanning.saving(DesktopGrid(panes: [pane(5)], frames: [left]), on: "B")!
    expectEqual(resaved.screens.map(\.displayID), ["A", "B"])
    expectEqual(resaved.screen(on: "B")!.grid.slots.map(\.binding), [binding(5)])
    expectEqual(resaved.screen(on: "A"), spanning.screen(on: "A"))
    expect(workspace.saving(missing, on: "B")!.screens.map(\.displayID) == ["B"], "A one-screen workspace moves to the screen it's saved from")
    expectEqual(spanning.saving(.emptyDesktop, on: "B")!.screens.map(\.displayID), ["A"])
    expect(workspace.saving(.emptyDesktop, on: "A") == nil, "Nothing left to save")

    // Quick Add joins: the workspace takes the split, and unrelated windows stay out.
    var arranged = DesktopGrid(panes: [pane(0), pane(1), pane(2), pane(8)],
                               frames: [left, topRight, bottomRight, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)])
    let newPane = arranged.split(0, toward: .bottom)!
    arranged.slots[newPane] = pane(7)
    let joined = workspace.joining(binding(7), arranged: arranged, on: "A")
    expectEqual(Set(joined.bindings), Set([binding(0), binding(1), binding(2), binding(7)]))
    expectFalse(joined.isModified(on: "A", showing: DesktopGrid(panes: [arranged.slots[0], arranged.slots[1], arranged.slots[2], arranged.slots[4]],
        frames: [arranged.normalizedFrames[0], topRight, bottomRight, arranged.normalizedFrames[4]])), "The join takes on the new split")
    let partlyAway = DesktopGrid(panes: [pane(0), pane(7), pane(8)], frames: [left, topRight, bottomRight])
    let joinedAway = workspace.joining(binding(7), arranged: partlyAway, on: "A")
    expect(Set(joinedAway.bindings) == Set([binding(0), binding(1), binding(2), binding(7)]),
           "Members that are minimized or on another desktop stay in the workspace when a window joins")
    expect(joinedAway.screens[0].grid.normalizedFrames.allSatisfy { $0.width > 0.2 && $0.height > 0.2 } && joinedAway.screens[0].grid.isValid,
           "The workspace makes room by splitting its own largest pane")
    expect(workspace.joining(binding(99), arranged: partlyAway, on: "A") == workspace, "A window that isn't arranged doesn't join")
    let joinedElsewhere = spanning.joining(binding(7), arranged: DesktopGrid(panes: [pane(7)], frames: [left]), on: "C")
    expectEqual(joinedElsewhere.screens.map(\.displayID), ["A", "B", "C"])

    // A screen in full screen switches to a regular desktop: last shown, then most windows, then first.
    expect(Workspace.regularDesktop(among: ["A|1", "A|2"], lastShown: "A|2", windows: ["A|1": 3]) == "A|2")
    expect(Workspace.regularDesktop(among: ["A|1", "A|2"], lastShown: "B|1", windows: ["A|2": 1]) == "A|2", "A desktop on another screen doesn't count")
    expect(Workspace.regularDesktop(among: ["A|1", "A|2"], lastShown: nil, windows: [:]) == "A|1")
    expect(Workspace.regularDesktop(among: [], lastShown: nil, windows: [:]) == nil, "No regular desktop to switch to")

    // Shown: per screen and desktop, replaced by the next workspace or cleared by a layout.
    var shown = ShownWorkspaces()
    shown.show(workspace.id, on: "A", desktop: "A|1")
    expectEqual(shown.workspace(on: "A", desktop: "A|1"), workspace.id)
    expect(shown.workspace(on: "A", desktop: "A|2") == nil, "Another desktop on that screen isn't showing it")
    shown.show(spanning.id, on: "A", desktop: "A|1")
    shown.show(spanning.id, on: "B", desktop: "B|1")
    expectEqual(shown.workspace(on: "A", desktop: "A|1"), spanning.id)
    expectEqual(shown.displays(showing: spanning.id), ["A", "B"])
    shown.clear("A")
    expectEqual(shown.displays(showing: spanning.id), ["B"])
    shown.forget(spanning.id)
    expect(shown.screens.isEmpty)
    print("PASS: workspaces keep only live windows, grow neighbors on close, follow one screen or return to several, detect edits, save per screen, join Quick Add windows, and track the shown workspace")
}
