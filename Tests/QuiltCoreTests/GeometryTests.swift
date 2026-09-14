import Foundation
import CoreGraphics
import QuiltCore

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
    // Persistence preserves session, order, settings, and identity across Quilt restarts.
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
        checkDesktopGrids()
        checkSavedSetups()
        checkActiveLayouts()
        checkMenuPanelGeometry()
        print("PASS: 31 geometry, matching, creation, visibility, saved-setup, active-layout, and menu-panel scenarios, \(assertionCount) assertions.")
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
