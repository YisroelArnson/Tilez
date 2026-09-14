import AppKit
import ApplicationServices
import QuiltCore

struct GridLaunchResult {
    let grid: DesktopGrid
    let exact: Bool
    let message: String
}

enum GridLaunchError: LocalizedError {
    case changedDesktop, missingApp(String), windowMissing(String), timedOut(String)
    var errorDescription: String? {
        switch self {
        case .changedDesktop: return "The desktop changed. Bring Quilt back on the desktop you want and try again."
        case .missingApp(let app): return "\(app) is not installed. Choose another app for its cell."
        case .windowMissing(let app): return "\(app)’s window is unavailable here. Open it on this desktop and try again."
        case .timedOut(let app): return "\(app) didn’t open another window. Check the app for a dialog, or choose a different app."
        }
    }
}

/// Reuses only target-desktop windows. New windows may inherit an app's full-screen Space;
/// prepare those exact new windows and return them to the captured destination before tiling.
@MainActor enum GridLauncher {
    static func open(_ request: DesktopGrid, display: Display, desktop: Desktop, manager: WindowManager,
                     progress: @escaping (String) -> Void,
                     prepared: @escaping (Int, GridWindowBinding) -> Void) async throws -> GridLaunchResult {
        func checkLocation() throws {
            try Task.checkCancellation()
            guard Display.all.contains(where: { $0.id == display.id }),
                  Desktops.all().contains(where: { $0.number == desktop.number }) else {
                throw GridLaunchError.changedDesktop
            }
        }
        func eligible(_ window: ManagedWindow) -> Bool {
            guard window.availability.accessible, window.availability.resizable,
                  !window.availability.fullScreen, window.availability.document,
                  let number = window.number else { return false }
            return Desktops.spaces(for: number).contains(desktop.number)
                && Display.containing(window.frame)?.id == display.id
        }
        try checkLocation()
        var resolved = request
        var seenWindows: [String: ManagedWindow] = [:]
        let appOrder = request.slots.compactMap(\.app).reduce(into: [GridApp]()) { result, app in
            if !result.contains(where: { $0.bundleID == app.bundleID }) { result.append(app) }
        }
        for choice in appOrder {
            try checkLocation()
            manager.suppressUntil = Date().addingTimeInterval(30)
            progress("Opening \(choice.name)…")
            // Snapshot WindowServer before launch/reopen so inherited full-screen windows can
            // be distinguished from pre-existing windows on unrelated desktops.
            let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: choice.bundleID).first
            let initialNumbers = runningApp.map { Desktops.existingWindowNumbers(pid: $0.processIdentifier) } ?? []
            let app: NSRunningApplication
            let wasRunning: Bool
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: choice.bundleID).first {
                app = running; wasRunning = true
            } else {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleID) else {
                    throw GridLaunchError.missingApp(choice.name)
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                wasRunning = false
            }
            try checkLocation()
            app.unhide()
            let indices = request.slots.indices.filter { request.slots[$0].app?.bundleID == choice.bundleID }
            let pid = app.processIdentifier
            guard let session = manager.processSession(pid) else { throw Accessibility.NewWindowError.appClosed }
            var selected: [String] = []
            func candidates() -> [ManagedWindow] {
                manager.refresh()
                let live = manager.windows.filter { $0.pid == pid }
                for window in live { seenWindows[window.id] = window }
                return live.filter { window in
                    if eligible(window) { return true }
                    guard let number = window.number, !initialNumbers.contains(number),
                          window.availability.document else { return false }
                    return window.availability.resizable || window.availability.fullScreen
                }
            }
            // Give a freshly launched application time to create its initial window.
            if !wasRunning {
                for _ in 0..<20 {
                    try checkLocation()
                    if !candidates().isEmpty { break }
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            do {
                selected = try await WindowCount.prepare(target: indices.count, current: {
                    try checkLocation()
                    let live = candidates()
                    let preferred = indices.compactMap { request.slots[$0].binding }
                        .filter { $0.processSession == session }.map(\.windowID)
                    let ordered = preferred.compactMap { id in live.first { $0.id == id } }
                        + live.filter { !preferred.contains($0.id) }
                    var seen = Set<String>()
                    return ordered.map(\.id).filter { seen.insert($0).inserted }
                }, requestNew: {
                    try checkLocation()
                    // Some apps publish New Window only while active. Their new windows may
                    // inherit full screen, which is handled below using exact WindowServer IDs.
                    app.activate()
                    try await Task.sleep(nanoseconds: 250_000_000)
                    try Task.checkCancellation()
                    if let item = Accessibility.newWindowCommand(pid: pid) {
                        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else {
                            throw Accessibility.NewWindowError.failed
                        }
                    } else if candidates().isEmpty, let url = app.bundleURL {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = false
                        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    } else { throw Accessibility.NewWindowError.unavailable(choice.name) }
                }, wait: { try await Task.sleep(nanoseconds: 250_000_000) }, progress: { count in
                    progress("\(choice.name) · \(min(count, indices.count)) of \(indices.count) windows ready")
                })
            } catch WindowCountError.windowDidNotAppear { throw GridLaunchError.timedOut(choice.name) }
            // Preserve surviving bindings in their exact cells before filling any gaps.
            var unused = selected
            var assigned: [Int: String] = [:]
            for index in indices {
                if let binding = request.slots[index].binding, binding.processSession == session,
                   let position = unused.firstIndex(of: binding.windowID) {
                    assigned[index] = unused.remove(at: position)
                }
            }
            for index in indices where assigned[index] == nil { assigned[index] = unused.removeFirst() }
            for index in indices {
                let binding = GridWindowBinding(windowID: assigned[index]!, processSession: session)
                resolved.slots[index].binding = binding
                prepared(index, binding)
            }
            // Wait for inherited full-screen transitions before asking those new windows to exit.
            try await Task.sleep(nanoseconds: 900_000_000)
            _ = candidates()
            var targets: [ManagedWindow] = []
            for id in selected {
                try checkLocation()
                _ = candidates()
                guard let window = seenWindows[id] else { throw GridLaunchError.windowMissing(choice.name) }
                progress("Preparing \(choice.name) for this desktop…")
                manager.suppressUntil = Date().addingTimeInterval(30)
                _ = try await Accessibility.prepareForTiling(window, preserveFullScreen: false)
                _ = candidates()
                targets.append(seenWindows[id] ?? window)
            }
            try await Desktops.move(targets, to: desktop)
            try await Desktops.activate(desktop)
        }
        try checkLocation()
        progress("Arranging your windows…")
        try await Desktops.activate(desktop)
        // AX can lag the Space transition, especially for Electron windows.
        for _ in 0..<30 {
            try checkLocation()
            manager.refresh()
            let ids = resolved.slots.compactMap { $0.binding?.windowID }
            if ids.allSatisfy({ id in manager.windows.contains { $0.id == id && $0.availability.accessible && !$0.availability.fullScreen } }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // Frame calculation includes empty cells; they remain empty on the desktop too.
        let frames = Geometry.grid(count: resolved.slots.count, in: display.bounds,
                                   columns: resolved.columns, rows: resolved.rows, gap: 10)
        var changes: [(ManagedWindow, CGRect)] = []
        for (index, slot) in resolved.slots.enumerated() {
            guard let choice = slot.app else { continue }
            guard let binding = slot.binding,
                  let window = manager.windows.first(where: {
                      $0.id == binding.windowID && $0.availability.accessible && !$0.availability.fullScreen
                          && $0.number.map { Desktops.spaces(for: $0).contains(desktop.number) } == true
                  }),
                  manager.processSession(window.pid) == binding.processSession else {
                throw GridLaunchError.windowMissing(choice.name)
            }
            if window.availability.minimized {
                guard AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else {
                    throw GridLaunchError.windowMissing(choice.name)
                }
            }
            changes.append((window, frames[index]))
        }
        try checkLocation()
        manager.apply(changes, label: "Open grid")
        for (window, _) in changes { AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
        // AX setters can return before Electron commits its bounds. Verify settled frames,
        // and retry once after the transition rather than reporting a false minimum-size error.
        for attempt in 0..<10 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 150_000_000)
            let unsettled = changes.filter { window, target in
                guard let actual = Accessibility.rect(window.element) else { return true }
                return !Geometry.approximatelyEqual(actual, target, tolerance: 6)
            }
            if unsettled.isEmpty { break }
            if attempt == 3 { for (window, target) in unsettled { _ = Accessibility.move(window, to: target) } }
        }
        let constrained = changes.filter { window, target in
            guard let actual = Accessibility.rect(window.element) else { return true }
            return !Geometry.approximatelyEqual(actual, target, tolerance: 6)
        }.count
        return GridLaunchResult(grid: resolved, exact: constrained == 0,
            message: "\(constrained) window\(constrained == 1 ? " has" : "s have") a minimum size or couldn’t be moved. Try fewer rows or columns.")
    }
}
