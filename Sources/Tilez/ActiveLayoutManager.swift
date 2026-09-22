import AppKit
import ApplicationServices
import TilezCore

struct RunningLayout: Identifiable {
    let id: String
    let record: ActiveLayout
    let windows: [ManagedWindow]
    let detected: Bool
    let location: String
    var pid: pid_t { windows.first?.pid ?? -1 }
}

enum ActiveLayoutError: LocalizedError {
    case changed, cannotClose(String), needsAttention(String)
    var errorDescription: String? {
        switch self {
        case .changed: return "This set has changed or its app has restarted. Refresh Active layouts and try again."
        case .cannotClose(let title): return "Could not close “\(title)”. Check the app for a save or confirmation dialog. Stopped; the remaining windows stay open."
        case .needsAttention(let title): return "“\(title)” is still open. Resolve any save or confirmation dialog in the app, then try again. Tilez has stopped closing windows."
        }
    }
}

extension WindowManager {
    func addPane(to layout: RunningLayout) {
        guard layout.windows.count < 40 else { status = "A layout can contain up to 40 panes."; return }
        var setup = layout.record.setup
        setup.count = layout.windows.count + 1
        changeActiveLayout(layout, setup: setup, keeping: Set(layout.record.windowIDs))
    }

    func closeAllPanes(in layout: RunningLayout) {
        changeActiveLayout(layout, setup: layout.record.setup, keeping: [], closeAll: true)
    }

    func processSession(_ pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid), let launch = app.launchDate else { return nil }
        // System boot + process launch are stable across Tilez restarts, but not PID reuse.
        return "\(pid)|\(launch.timeIntervalSince1970)|\(app.bundleIdentifier ?? "")"
    }

    func reconcileActiveLayouts() {
        var live: [String: Set<String>] = [:]
        for group in groups {
            if let session = processSession(group.pid) { live[session] = Set(group.windows.map(\.id)) }
        }
        let next = ActiveLayouts.reconcile(preferences.activeLayouts, live: live)
        if next != preferences.activeLayouts { preferences.activeLayouts = next }
    }

    var runningLayouts: [RunningLayout] {
        let spaces = Desktops.all(includeFullScreen: true)
        func location(_ windows: [ManagedWindow]) -> String {
            let numbers = windows.reduce(into: Set<UInt64>()) { result, window in
                if let number = window.number { result.formUnion(Desktops.spaces(for: number)) }
            }
            let found = spaces.filter { numbers.contains($0.number) }
            if found.isEmpty { return "Desktop unavailable" }
            return found.map { $0.isFullScreen ? "Full screen · \($0.displayName)" : $0.title }.joined(separator: " · ")
        }
        var result: [RunningLayout] = []
        var claimed = Set<String>()
        for record in preferences.activeLayouts {
            let members = windows.filter { record.windowIDs.contains($0.id) && processSession($0.pid) == record.processSession }
            guard !members.isEmpty else { continue }
            let ordered = record.windowIDs.compactMap { id in members.first { $0.id == id } }
            claimed.formUnion(ordered.map(\.id))
            result.append(RunningLayout(id: record.id.uuidString, record: record, windows: ordered, detected: false, location: location(ordered)))
        }
        // Existing sets predate tracking. Only infer a set when membership has one unambiguous Space.
        var detected: [String: [ManagedWindow]] = [:]
        for window in windows where !claimed.contains(window.id) {
            guard let session = processSession(window.pid), let number = window.number else { continue }
            let membership = Desktops.spaces(for: number)
            let key = membership.count == 1 ? "\(session)|\(membership.first!)" : "\(session)|window|\(window.id)"
            detected[key, default: []].append(window)
        }
        for key in detected.keys.sorted() {
            guard let members = detected[key], let first = members.first, let session = processSession(first.pid) else { continue }
            let memberships = first.number.map { Desktops.spaces(for: $0) } ?? []
            let desktop = spaces.first { memberships.contains($0.number) }
            let display = Display.containing(first.frame)
            let setup = WindowSetup(name: first.appName, bundleID: first.bundleID, appName: first.appName,
                count: min(40, members.count), columns: 0, rows: 0, gap: preferences.gap,
                displayID: desktop?.displayID ?? display?.id ?? "", desktop: desktop?.id ?? "current",
                preserveFullScreen: members.contains { $0.availability.fullScreen })
            result.append(RunningLayout(id: "detected|\(key)", record: ActiveLayout(processSession: session, windowIDs: members.map(\.id), setup: setup),
                windows: members, detected: true, location: location(members)))
        }
        return result
    }

    func recordActiveLayout(pid: pid_t, ids: [String], setup: WindowSetup, destination: Desktop, id: UUID?) {
        guard let session = processSession(pid) else { return }
        var resolved = setup
        resolved.desktop = destination.id; resolved.displayID = destination.displayID
        resolved.freshWindows = false
        let record = ActiveLayout(id: id ?? UUID(), processSession: session, windowIDs: ids, setup: resolved)
        preferences.activeLayouts = ActiveLayouts.recording(record, in: preferences.activeLayouts)
    }

    private func windowHasClosed(_ window: ManagedWindow) -> Bool {
        guard let number = window.number else { return false }
        if !Desktops.existingWindowNumbers(pid: window.pid).contains(number) { return true }
        // NSWindow can remain allocated (and in WindowServer) after a normal close.
        // Only accept AX absence on its still-visible Space, with a responsive, unhidden app.
        guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isHidden,
              let raw = Accessibility.value(AXUIElementCreateApplication(window.pid), kAXWindowsAttribute) as? [AXUIElement],
              !raw.contains(where: { Desktops.windowNumber($0) == number }) else { return false }
        let membership = Desktops.spaces(for: number)
        let current = Set(Desktops.all(includeFullScreen: true).filter(\.isCurrent).map(\.number))
        return !membership.isEmpty && membership.isSubset(of: current)
    }

    /// Only the window IDs shown in the editor are eligible for closing or reuse.
    func changeActiveLayout(_ layout: RunningLayout, setup: WindowSetup, keeping: Set<String>, closeAll: Bool = false) {
        guard trusted, openingPID == nil else { status = "Finish the current request and enable Accessibility first."; return }
        guard processSession(layout.pid) == layout.record.processSession else { status = ActiveLayoutError.changed.localizedDescription; return }
        let members = layout.record.windowIDs
        let retained = keeping.intersection(Set(members))
        guard closeAll || (setup.isValid && retained.count == min(setup.count, members.count)) else {
            status = "Choose exactly the windows you want to keep."; return
        }
        let closing = closeAll ? members : ActiveLayouts.closing(members: members, keeping: retained)
        openingPID = layout.pid
        openingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var continueWithTiling = false
            defer {
                self.watchMembership[layout.pid] = Set(self.windows.filter { $0.pid == layout.pid && $0.availability.automatic }.map(\.id))
                self.openingPID = nil; self.openingTask = nil
                self.suppressUntil = Date().addingTimeInterval(1)
                if continueWithTiling {
                    var request = setup
                    request.freshWindows = false
                    self.openAndTile(pid: layout.pid, count: request.count, preferredIDs: retained,
                        setup: request, activeLayoutID: layout.record.id, allowedExistingIDs: retained)
                }
            }
            do {
                // Retain the exact set even if a close is cancelled or blocked by an app dialog.
                self.preferences.activeLayouts = ActiveLayouts.recording(layout.record, in: self.preferences.activeLayouts)
                for (index, id) in closing.enumerated() {
                    try Task.checkCancellation()
                    guard self.processSession(layout.pid) == layout.record.processSession else { throw ActiveLayoutError.changed }
                    self.refresh()
                    guard let candidate = self.windows.first(where: { $0.id == id && $0.pid == layout.pid }) else { continue }
                    if let number = candidate.number,
                       let desktop = Desktops.all(includeFullScreen: true).first(where: { Desktops.spaces(for: number).contains($0.number) }) {
                        try await Desktops.activate(desktop)
                    }
                    NSRunningApplication(processIdentifier: layout.pid)?.unhide()
                    self.refresh()
                    if self.windowHasClosed(candidate) { Accessibility.markClosed(candidate); continue }
                    guard let window = self.windows.first(where: { $0.id == id }), window.availability.accessible else { throw ActiveLayoutError.cannotClose(candidate.title) }
                    if self.windowHasClosed(window) { Accessibility.markClosed(window); continue }
                    let title = window.title.isEmpty ? window.appName : window.title
                    self.status = "Closing \(index + 1) of \(closing.count) windows in \(layout.record.setup.name)…"
                    self.suppressUntil = Date().addingTimeInterval(10)
                    guard let close = Accessibility.value(window.element, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID(),
                          AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success else {
                        throw ActiveLayoutError.cannotClose(title)
                    }
                    var closed = false
                    for _ in 0..<30 {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        closed = self.windowHasClosed(window)
                        if closed { break }
                    }
                    guard closed else { throw ActiveLayoutError.needsAttention(title) }
                    Accessibility.markClosed(window)
                }
                self.refresh()
                if closeAll {
                    self.status = "Closed \(closing.count) windows in \(layout.record.setup.name). Other sets stay open."
                } else {
                    // Do not replace an original member that disappeared while the editor was open.
                    guard retained.isSubset(of: Set(self.windows.map(\.id))) else { throw ActiveLayoutError.changed }
                    continueWithTiling = true
                }
            } catch is CancellationError {
                self.status = "Stopped. Any windows already closed stay closed; the remaining windows stay open."
            } catch { self.status = error.localizedDescription }
        }
    }
}
