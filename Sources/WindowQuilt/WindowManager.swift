import AppKit
import Combine
import QuiltCore

struct AppGroup: Identifiable {
    let pid: pid_t
    let name: String
    let windows: [ManagedWindow]
    var id: pid_t { pid }
    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

private struct WindowState {
    let window: ManagedWindow
    let frame: CGRect
}
private struct UndoEntry {
    let label: String
    let states: [WindowState]
}

final class WindowManager: ObservableObject {
    let preferences: Preferences
    @Published var windows: [ManagedWindow] = []
    @Published var trusted = Accessibility.trusted
    @Published var watched: Set<pid_t> = []
    @Published var status = "Choose an app to arrange its windows."
    @Published var undoLabel: String?
    @Published var shortcutError = ""
    @Published var desktops: [Desktop] = Desktops.all()
    @Published var openingPID: pid_t?
    @Published var preparedWindowIDs: [String] = []
    var openingTask: Task<Void, Never>?
    var onDraw: ((ManagedWindow) -> Void)?
    var onPermissionChange: (() -> Void)?
    private var timer: Timer?
    private var undoStack: [UndoEntry] = []
    private var baseline: [String: WindowState] = [:]
    private var pendingManual: [String: WindowState] = [:]
    private var lastMotion = Date.distantPast
    var suppressUntil = Date.distantPast
    var watchMembership: [pid_t: Set<String>] = [:]
    private var stableOrder: [String: Int] = [:]
    private var nextOrder = 0
    private var lastExternalPID: pid_t?
    private var lastSnap: (id: String, placement: Placement, cycle: Int, date: Date)?
    private var displayWork: DispatchWorkItem?
    private let backgroundArrangements: Bool

    var groups: [AppGroup] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .map { app in
                AppGroup(pid: app.processIdentifier, name: app.localizedName ?? "App",
                         windows: windows.filter { $0.pid == app.processIdentifier })
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    init(preferences: Preferences, backgroundArrangements: Bool = true) {
        self.preferences = preferences
        self.backgroundArrangements = backgroundArrangements
        let t = Timer(timeInterval: 0.85, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
    }

    func refresh() {
        let currentDesktops = Desktops.all()
        if desktops != currentDesktops { desktops = currentDesktops }
        let allowed = Accessibility.trusted
        if trusted != allowed { trusted = allowed; onPermissionChange?() }
        guard trusted else { windows = []; return }
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            lastExternalPID = app.processIdentifier
        }
        let live = Accessibility.windows()
        for window in live where stableOrder[window.id] == nil {
            stableOrder[window.id] = nextOrder
            nextOrder += 1
        }
        let ids = Set(live.map(\.id))
        stableOrder = stableOrder.filter { ids.contains($0.key) }
        windows = live.sorted { (stableOrder[$0.id] ?? 0) < (stableOrder[$1.id] ?? 0) }
        reconcileActiveLayouts()
        recordManualMoves()
        for pid in watched where pid != openingPID {
            if NSRunningApplication(processIdentifier: pid) == nil {
                watched.remove(pid); watchMembership.removeValue(forKey: pid)
                continue
            }
            let current = Set(windows.filter { $0.pid == pid && $0.availability.automatic }.map(\.id))
            if watchMembership[pid] != current && NSEvent.pressedMouseButtons == 0 {
                watchMembership[pid] = current
                tileWindows(windows.filter { $0.pid == pid && $0.availability.automatic }, label: "Watch app")
            }
        }
    }

    func focused() -> ManagedWindow? {
        Accessibility.focused(in: windows, fallbackPID: lastExternalPID)
    }

    private func recordManualMoves() {
        let now = Date()
        if now < suppressUntil {
            baseline = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, WindowState(window: $0, frame: $0.frame)) })
            pendingManual.removeAll()
            return
        }
        for window in windows where window.availability.automatic {
            if let previous = baseline[window.id], previous.window.availability.automatic, !Geometry.approximatelyEqual(previous.frame, window.frame) {
                if pendingManual[window.id] == nil { pendingManual[window.id] = previous }
                lastMotion = now
            }
            baseline[window.id] = WindowState(window: window, frame: window.frame)
        }
        let currentIDs = Set(windows.map(\.id))
        baseline = baseline.filter { currentIDs.contains($0.key) }
        pendingManual = pendingManual.filter { currentIDs.contains($0.key) }
        if NSEvent.pressedMouseButtons == 0 && now.timeIntervalSince(lastMotion) > 0.45 && !pendingManual.isEmpty {
            if preferences.undoManual { pushUndo("Manual window move", states: Array(pendingManual.values)) }
            pendingManual.removeAll()
        }
    }

    private func pushUndo(_ label: String, states: [WindowState]) {
        guard !states.isEmpty else { return }
        undoStack.append(UndoEntry(label: label, states: states))
        if undoStack.count > 50 { undoStack.removeFirst() }
        undoLabel = label
    }

    func apply(_ changes: [(ManagedWindow, CGRect)], label: String, recordUndo: Bool = true) {
        guard trusted else { status = "Enable Accessibility in System Settings first."; return }
        let actual = changes.filter { window, rect in
            !Geometry.approximatelyEqual(Accessibility.rect(window.element) ?? window.frame, rect)
        }
        guard !actual.isEmpty else { status = "Windows are already in place."; return }
        if recordUndo {
            // Include the beginning of an in-progress manual drag in the same undo action.
            pushUndo(label, states: actual.map { window, _ in
                pendingManual[window.id] ?? WindowState(window: window, frame: window.frame)
            })
        }
        pendingManual.removeAll()
        suppressUntil = Date().addingTimeInterval(0.9)
        var failed = 0, constrained = 0
        for (window, target) in actual {
            if !Accessibility.move(window, to: target) { failed += 1 }
            else if let frame = Accessibility.rect(window.element), !Geometry.approximatelyEqual(frame, target, tolerance: 4) { constrained += 1 }
        }
        status = "\(label): \(actual.count - failed) window\(actual.count == 1 ? "" : "s") arranged."
        if constrained > 0 { status += " \(constrained) limited by the app’s minimum size." }
        if failed > 0 { status += " \(failed) could not be moved." }
        windows = windows.map { old in
            ManagedWindow(element: old.element, pid: old.pid, bundleID: old.bundleID, appName: old.appName, title: old.title,
                          frame: Accessibility.rect(old.element) ?? old.frame, availability: old.availability, serverNumber: old.number)
        }
        baseline = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, WindowState(window: $0, frame: $0.frame)) })
    }

    func openAndTile(pid: pid_t, count: Int, preferredIDs: Set<String> = [], setup: WindowSetup? = nil, activeLayoutID: UUID? = nil, allowedExistingIDs: Set<String>? = nil) {
        guard openingPID == nil else { status = "A window request is already running."; return }
        guard trusted else { status = "Enable Accessibility in System Settings first."; return }
        guard (1...40).contains(count) else { status = "Choose between 1 and 40 windows."; return }
        guard let app = NSRunningApplication(processIdentifier: pid) else { status = "The selected app has closed."; return }
        let name = app.localizedName ?? "App"
        let request = setup ?? WindowSetup(name: name, bundleID: app.bundleIdentifier ?? "", appName: name,
            count: count, columns: preferences.columns, rows: preferences.rows, gap: preferences.gap,
            displayID: preferences.gatherDisplay, desktop: preferences.desktop, freshWindows: preferences.freshWindows, preserveFullScreen: preferences.preserveFullScreen)
        openingPID = pid
        preparedWindowIDs = []
        openingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.watchMembership[pid] = Set(self.windows.filter { $0.pid == pid && $0.availability.automatic }.map(\.id))
                self.openingPID = nil
                self.openingTask = nil
                self.suppressUntil = Date().addingTimeInterval(1)
            }
            do {
                self.refresh()
                let existing = self.windows.filter { $0.pid == pid }
                let hasNewWindowCommand = Accessibility.newWindowCommand(pid: pid) != nil
                if !hasNewWindowCommand && (count > max(1, existing.count)
                    || (!existing.isEmpty && (request.freshWindows || request.desktop == "new"))) {
                    throw Accessibility.NewWindowError.unavailable(name)
                }
                let initialNumbers = Desktops.existingWindowNumbers(pid: pid)
                let display: Display
                if let explicitDesktop = Desktops.all().first(where: { $0.id == request.desktop }),
                   let screen = Display.all.first(where: { $0.id == explicitDesktop.displayID }) {
                    display = screen
                } else if request.displayID.isEmpty {
                    display = Display.all.first(where: { $0.screen == NSScreen.main }) ?? Display.all.first!
                } else {
                    guard let selected = Display.all.first(where: { $0.id == request.displayID }) else { throw DesktopError.missingDisplay }
                    display = selected
                }
                self.status = request.desktop == "new" ? "Creating a separate desktop…" : "Preparing the selected desktop…"
                let destination = try await Desktops.resolve(request.desktop, display: display)
                try Task.checkCancellation()
                app.unhide()
                if !hasNewWindowCommand && count == 1 {
                    self.status = "Reopening \(name)…"
                    try await Accessibility.reopen(app)
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                self.refresh()
                let initial = Set(self.windows.filter { $0.pid == pid }.map(\.id))
                let fresh = request.freshWindows || request.desktop == "new"
                app.activate()
                try await Task.sleep(nanoseconds: 300_000_000)
                var seenWindows: [String: ManagedWindow] = [:]
                var reopened = false
                let ids = try await WindowCount.prepare(target: count, current: {
                    self.refresh()
                    let live = self.windows.filter { $0.pid == pid }
                    for window in live { seenWindows[window.id] = window }
                    let onDestination = Set(live.filter {
                        // A full-screen window owns its own Space. An explicit current-desktop
                        // request can bring selected full-screen windows on this display into the grid.
                        if allowedExistingIDs?.contains($0.id) == true { return true }
                        if !fresh && ((!hasNewWindowCommand && count == 1)
                            || (request.desktop == "current" && $0.availability.fullScreen
                                && (preferredIDs.contains($0.id) || (preferredIDs.isEmpty && Display.containing($0.frame)?.id == display.id)))) { return true }
                        guard let number = $0.number else { return false }
                        return Desktops.spaces(for: number).contains(destination.number)
                    }.map(\.id))
                    let ordered: [String]
                    if !hasNewWindowCommand && count == 1 {
                        ordered = live.filter { $0.availability.accessible }.map(\.id)
                            + live.filter { !$0.availability.accessible }.map(\.id)
                    } else {
                        ordered = live.filter { preferredIDs.contains($0.id) }.map(\.id)
                            + live.filter { !preferredIDs.contains($0.id) }.map(\.id)
                    }
                    let preexisting = initial.union(live.filter {
                        guard let number = $0.number else { return true }
                        return initialNumbers.contains(number)
                    }.map(\.id))
                    let scoped = allowedExistingIDs.map { ActiveLayouts.eligible(live: ordered, initial: preexisting, members: $0) } ?? ordered
                    let eligible = Array(WindowSetup.eligibleIDs(live: scoped, initial: preexisting, onDestination: onDestination, fresh: fresh).prefix(count))
                    return eligible
                }, requestNew: {
                    if Accessibility.newWindowCommand(pid: pid) != nil {
                        try Accessibility.requestNewWindow(pid: pid)
                    } else if self.windows.filter({ $0.pid == pid }).isEmpty && !reopened {
                        reopened = true
                        try await Accessibility.reopen(app)
                    } else { throw Accessibility.NewWindowError.unavailable(name) }
                }, wait: {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }, progress: { available in
                    self.status = available < count
                        ? "Opening \(name) windows… \(available) of \(count) ready."
                        : "Arranging \(count) \(name) windows…"
                })
                try Task.checkCancellation()
                // Let a newly created window finish entering inherited full screen before exiting it.
                try await Task.sleep(nanoseconds: 900_000_000)
                self.refresh()
                for window in self.windows where ids.contains(window.id) { seenWindows[window.id] = window }
                for id in ids {
                    self.refresh()
                    for live in self.windows where ids.contains(live.id) { seenWindows[live.id] = live }
                    guard let window = seenWindows[id] else { continue }
                    self.suppressUntil = Date().addingTimeInterval(12)
                    self.status = "Preparing \(name) for tiling…"
                    _ = try await Accessibility.prepareForTiling(window, preserveFullScreen: request.keepsFullScreen)
                }
                self.refresh()
                for window in self.windows where ids.contains(window.id) { seenWindows[window.id] = window }
                let kept = ids.compactMap { seenWindows[$0] }.filter { request.keepsFullScreen && $0.availability.fullScreen }
                let targets = ids.compactMap { seenWindows[$0] }.filter { !(request.keepsFullScreen && $0.availability.fullScreen) }
                if targets.isEmpty {
                    self.preparedWindowIDs = ids
                    self.recordActiveLayout(pid: pid, ids: ids, setup: request, destination: destination, id: activeLayoutID)
                    self.status = "Kept \(kept.count) full-screen windows in their existing Spaces."
                    return
                }
                self.status = "Moving \(count) windows to \(destination.title)…"
                try await Desktops.move(targets, to: destination)
                try await Desktops.activate(destination)
                try Task.checkCancellation()
                let frames = Geometry.grid(count: targets.count, in: display.bounds, columns: request.columns, rows: request.rows, gap: request.gap)
                var ready: [ManagedWindow] = []
                for _ in 0..<25 {
                    self.refresh()
                    ready = targets.compactMap { target in self.windows.first { $0.id == target.id && $0.availability.accessible } }
                    if ready.count == targets.count { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard ready.count == targets.count else { throw Accessibility.NewWindowError.transition(name) }
                self.apply(Array(zip(ready, frames)), label: "Tile \(ready.count) \(name) windows")
                self.preparedWindowIDs = ids
                self.recordActiveLayout(pid: pid, ids: ids, setup: request, destination: destination, id: activeLayoutID)
                if !kept.isEmpty { self.status += " \(kept.count) full-screen windows kept in their Spaces." }
                let extras = self.windows.filter { $0.pid == pid }.count - ids.count
                if extras > 0 { self.status += " \(extras) additional windows stay open." }
            } catch is CancellationError {
                self.status = "Stopped opening windows. Any windows already opened remain available."
            } catch WindowCountError.windowDidNotAppear {
                self.status = "\(name) did not open a new independent window within 10 seconds. Stopped; check the app for a dialog or open its windows manually."
            } catch WindowCountError.windowsKeepClosing {
                self.status = "Windows kept closing while Quilt was opening them. Stopped; try again when the app is ready."
            } catch {
                self.status = error.localizedDescription
            }
        }
    }

    func runSetup(_ setup: WindowSetup) {
        guard setup.isValid else { status = "This setup is incomplete. Edit it first."; return }
        guard openingPID == nil else { status = "Finish or cancel the current request first."; return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: setup.bundleID).first {
            openAndTile(pid: app.processIdentifier, count: setup.count, setup: setup)
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: setup.bundleID) else {
            status = "\(setup.appName) is not installed."; return
        }
        openingPID = -1
        status = "Launching \(setup.appName)…"
        openingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                        if let app { continuation.resume(returning: app) }
                        else { continuation.resume(throwing: error ?? DesktopError.unavailable) }
                    }
                }
                try Task.checkCancellation()
                self.openingPID = nil
                self.openingTask = nil
                self.openAndTile(pid: app.processIdentifier, count: setup.count, setup: setup)
            } catch {
                self.openingPID = nil
                self.openingTask = nil
                self.status = error is CancellationError ? "Setup launch cancelled." : error.localizedDescription
            }
        }
    }

    func saveSetup(_ setup: WindowSetup) {
        guard setup.isValid else { status = "Choose a name, app, and valid window count."; return }
        if let index = preferences.setups.firstIndex(where: { $0.id == setup.id }) { preferences.setups[index] = setup }
        else { preferences.setups.append(setup) }
        status = "Saved setup “\(setup.name)”."
    }

    func cancelOpening() {
        openingTask?.cancel()
    }

    func tile(pid: pid_t, selected: Set<String>? = nil, refreshFirst: Bool = true) {
        if refreshFirst { refresh() }
        let targets = windows.filter { $0.pid == pid && (selected == nil || selected!.contains($0.id)) }
        guard openingPID == nil else { status = "Finish the current request first."; return }
        openingPID = pid
        openingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.openingPID = nil; self.openingTask = nil; self.suppressUntil = Date().addingTimeInterval(1) }
            do {
                var ready: Set<String> = []
                var kept = 0
                for window in targets {
                    self.status = "Preparing \(window.appName) windows…"
                    self.suppressUntil = Date().addingTimeInterval(12)
                    if try await Accessibility.prepareForTiling(window, preserveFullScreen: self.preferences.preserveFullScreen) { ready.insert(window.id) }
                    else { kept += 1 }
                }
                self.refresh()
                if ready.isEmpty { self.status = "No windows to tile." }
                else {
                    let groups = Dictionary(grouping: self.windows.filter { ready.contains($0.id) }) { window in
                        window.number.map { Desktops.spaces(for: $0).sorted().map(String.init).joined(separator: ",") } ?? ""
                    }
                    var outcomes: [String] = []
                    for group in groups.values {
                        if let number = group.first?.number,
                           let desktop = Desktops.all().first(where: { Desktops.spaces(for: number).contains($0.number) }) {
                            try await Desktops.activate(desktop)
                        }
                        self.refresh()
                        let groupIDs = Set(group.map(\.id))
                        let live = self.windows.filter { groupIDs.contains($0.id) && $0.availability.accessible }
                        guard live.count == group.count else { throw Accessibility.NewWindowError.transition(targets.first?.appName ?? "App") }
                        self.tileWindows(live, label: "Tile \(targets.first?.appName ?? "windows")")
                        outcomes.append(self.status)
                    }
                    self.status = outcomes.joined(separator: " ")
                }
                if kept > 0 { self.status += " Kept \(kept) full-screen windows in their Spaces." }
            } catch is CancellationError { self.status = "Arrangement cancelled." }
            catch { self.status = error.localizedDescription }
        }
    }

    func tileWindows(_ targets: [ManagedWindow], label: String) {
        guard !targets.isEmpty else { status = "No resizable windows available."; return }
        let displays = Display.all
        var changes: [(ManagedWindow, CGRect)] = []
        if let display = displays.first(where: { $0.id == preferences.gatherDisplay }) {
            let groups = Dictionary(grouping: targets) { window -> String in
                guard let number = window.number else { return "unknown" }
                return Desktops.spaces(for: number).sorted().map(String.init).joined(separator: ",")
            }
            for group in groups.values {
                let rects = Geometry.grid(count: group.count, in: display.bounds, columns: preferences.columns, rows: preferences.rows, gap: preferences.gap)
                changes += Array(zip(group, rects))
            }
        } else {
            let byDisplay = Dictionary(grouping: targets) { Display.containing($0.frame)?.id ?? "" }
            for display in displays {
                let groups = Dictionary(grouping: byDisplay[display.id] ?? []) { window -> String in
                    guard let number = window.number else { return "unknown" }
                    return Desktops.spaces(for: number).sorted().map(String.init).joined(separator: ",")
                }
                for group in groups.values {
                    let rects = Geometry.grid(count: group.count, in: display.bounds, columns: preferences.columns, rows: preferences.rows, gap: preferences.gap)
                    changes += Array(zip(group, rects))
                }
            }
        }
        apply(changes, label: label)
    }

    func toggleWatch(_ pid: pid_t) {
        if watched.contains(pid) {
            watched.remove(pid); watchMembership.removeValue(forKey: pid)
            status = "Watch mode stopped."
        } else {
            watched.insert(pid)
            watchMembership[pid] = Set(windows.filter { $0.pid == pid && $0.availability.automatic }.map(\.id))
            tileWindows(windows.filter { $0.pid == pid && $0.availability.automatic }, label: "Watch app")
        }
    }

    func snap(_ placement: Placement, window: ManagedWindow? = nil, cycle: Bool = true, display: Display? = nil) {
        guard let w = window ?? focused(), let d = display ?? Display.containing(w.frame) else { status = "Focus a resizable window first."; return }
        guard w.availability.automatic else { status = "Use Arrange to restore this window before snapping."; return }
        var index = 0
        if cycle, let last = lastSnap, last.id == w.id, last.placement == placement, Date().timeIntervalSince(last.date) < 2 {
            index = (last.cycle + 1) % 3
        }
        lastSnap = (w.id, placement, index, Date())
        let target = Geometry.placement(placement, in: d.bounds, current: Accessibility.rect(w.element) ?? w.frame, cycle: index, gap: preferences.gap)
        apply([(w, target)], label: placement.title.components(separatedBy: " •").first ?? placement.title)
    }

    func execute(_ command: Command) {
        refresh()
        if let placement = command.placement { snap(placement); return }
        switch command {
        case .tile:
            if let window = focused() { tile(pid: window.pid) }
            else { status = "Focus a resizable window first." }
        case .undo: undo()
        case .draw:
            if let window = focused() { onDraw?(window) }
            else { status = "Focus a resizable window first." }
        case .nextDisplay, .previousDisplay:
            guard let window = focused(), let current = Display.containing(window.frame) else { return }
            let displays = Display.all.sorted { $0.bounds.minX == $1.bounds.minX ? $0.bounds.minY < $1.bounds.minY : $0.bounds.minX < $1.bounds.minX }
            guard displays.count > 1, let index = displays.firstIndex(where: { $0.id == current.id }) else { status = "Connect another display to move windows between screens."; return }
            let offset = command == .nextDisplay ? 1 : displays.count - 1
            let destination = displays[(index + offset) % displays.count]
            let normalized = Geometry.normalized(window.frame, in: current.bounds)
            apply([(window, Geometry.restored(normalized, in: destination.bounds))], label: "Move to \(destination.name)")
        default: break
        }
    }

    func undo() {
        if !pendingManual.isEmpty {
            pushUndo("Manual window move", states: Array(pendingManual.values))
            pendingManual.removeAll()
        }
        guard let entry = undoStack.popLast() else { status = "Nothing to undo yet."; return }
        undoLabel = undoStack.last?.label
        let liveIDs = Set(windows.map(\.id))
        let changes = entry.states.filter { liveIDs.contains($0.window.id) }.map { ($0.window, $0.frame) }
        if changes.isEmpty { status = "Those windows have closed."; return }
        apply(changes, label: "Undo \(entry.label)", recordUndo: false)
    }

    func saveLayout(name: String) {
        refresh()
        var ordinals: [String: Int] = [:]
        let records: [SavedWindow] = windows.filter { $0.availability.automatic }.compactMap { window in
            guard let display = Display.containing(window.frame) else { return nil }
            let ordinal = ordinals[window.bundleID, default: 0]
            ordinals[window.bundleID] = ordinal + 1
            return SavedWindow(bundleID: window.bundleID, title: window.title, ordinal: ordinal, displayID: display.id,
                               normalized: Geometry.normalized(window.frame, in: display.bounds))
        }
        guard !records.isEmpty else { status = "Open some resizable windows before saving a layout."; return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.layouts.append(SavedLayout(name: clean.isEmpty ? "Layout \(preferences.layouts.count + 1)" : clean, windows: records, topology: Display.topology))
        status = "Saved \(records.count) windows."
    }

    func restore(_ layout: SavedLayout) {
        refresh()
        let displays = Display.all
        let available = windows.filter { $0.availability.automatic }
        var ordinals: [String: Int] = [:]
        let identities = available.map { window -> WindowIdentity in
            let ordinal = ordinals[window.bundleID, default: 0]
            ordinals[window.bundleID] = ordinal + 1
            return WindowIdentity(app: window.bundleID, title: window.title, ordinal: ordinal)
        }
        let matches = LayoutMatcher.match(saved: layout.windows.map {
            WindowIdentity(app: $0.bundleID, title: $0.title, ordinal: $0.ordinal)
        }, live: identities)
        var changes: [(ManagedWindow, CGRect)] = []
        for (index, saved) in layout.windows.enumerated() {
            guard let match = matches[index] else { continue }
            let window = available[match]
            guard let display = displays.first(where: { $0.id == saved.displayID }) ?? Display.containing(window.frame) ?? displays.first else { continue }
            changes.append((window, Geometry.restored(saved.normalized, in: display.bounds)))
        }
        apply(changes, label: "Restore \(layout.name)")
        let missing = layout.windows.count - changes.count
        if missing > 0 { status += " \(missing) saved windows are not open." }
    }

    func pinLayout(_ id: UUID, enabled: Bool) {
        guard let index = preferences.layouts.firstIndex(where: { $0.id == id }) else { return }
        let topology = preferences.layouts[index].topology
        if enabled {
            for i in preferences.layouts.indices where preferences.layouts[i].topology == topology { preferences.layouts[i].autoRestore = false }
        }
        preferences.layouts[index].autoRestore = enabled
    }

    @objc private func displaysChanged() {
        guard backgroundArrangements else { refresh(); return }
        displayWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let topology = Display.topology
            if let layout = self.preferences.layouts.first(where: { $0.autoRestore && $0.topology == topology }) { self.restore(layout) }
            else {
                self.refresh()
                for pid in self.watched { self.tileWindows(self.windows.filter { $0.pid == pid && $0.availability.automatic }, label: "Watch app") }
            }
        }
        displayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
