import AppKit
import ApplicationServices
import TilezCore

struct GridLaunchResult {
    let grid: DesktopGrid
    let exact: Bool
    let message: String
}

enum GridLaunchError: LocalizedError {
    case changedDesktop, missingApp(String), windowMissing(String), timedOut(String)
    var errorDescription: String? {
        switch self {
        case .changedDesktop: return "The desktop changed. Bring Tilez back on the desktop you want and try again."
        case .missingApp(let app): return "\(app) is not installed. Choose another app for its cell."
        case .windowMissing(let app): return "\(app)’s window is unavailable here. Open it on this desktop and try again."
        case .timedOut(let app): return "\(app) didn’t open another window. Check the app for a dialog, or choose a different app."
        }
    }
}

/// Reuses only target-desktop windows. New windows may inherit an app's full-screen Space;
/// prepare those exact new windows and return them to the captured destination before tiling.
@MainActor enum GridLauncher {
    static func open(_ request: DesktopGrid, display capturedDisplay: Display, desktop capturedDesktop: Desktop, manager: WindowManager,
                     original: DesktopGrid? = nil, destinationChanged: (Display, Desktop) -> Void = { _, _ in }, progress: @escaping (String) -> Void,
                     prepared: @escaping (Int, GridWindowBinding) -> Void) async throws -> GridLaunchResult {
        var display = capturedDisplay
        try Task.checkCancellation()
        guard Desktops.current(displayID: display.id, includeFullScreen: true)?.number == capturedDesktop.number else {
            throw GridLaunchError.changedDesktop
        }
        if request == original { return GridLaunchResult(grid: request, exact: true, message: "") }
        var desktop = capturedDesktop
        // A native full-screen Space cannot contain an arbitrary tiled layout. Exit
        // that exact window first; use the regular desktop macOS returns it to.
        if capturedDesktop.isFullScreen {
            guard let source = (original ?? request).slots.first(where: { $0.binding != nil }),
                  let binding = source.binding, let choice = source.app,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: choice.bundleID).first,
                  manager.processSession(app.processIdentifier) == binding.processSession else {
                throw GridLaunchError.changedDesktop
            }
            let live = try await Accessibility.windows(for: [app.processIdentifier])
            guard let window = live.first(where: { $0.id == binding.windowID }) else { throw GridLaunchError.windowMissing(choice.name) }
            progress("Leaving full screen to edit this desktop…")
            _ = try await Accessibility.prepareForTiling(window, preserveFullScreen: false)
            guard let destination = Desktops.current(displayID: display.id) else { throw GridLaunchError.changedDesktop }
            desktop = destination
            guard let currentDisplay = Display.all.first(where: { $0.id == capturedDisplay.id }) else { throw GridLaunchError.changedDesktop }
            display = currentDisplay
            destinationChanged(display, desktop)
        }
        func checkLocation() throws {
            try Task.checkCancellation()
            guard Display.all.contains(where: { $0.id == display.id }),
                  Desktops.all().contains(where: { $0.number == desktop.number }) else {
                throw GridLaunchError.changedDesktop
            }
        }
        func eligible(_ window: ManagedWindow) -> Bool {
            guard window.availability.accessible,
                  !window.availability.fullScreen, window.availability.document,
                  let number = window.number else { return false }
            return Desktops.spaces(for: number).contains(desktop.number)
                && Display.containing(window.frame)?.id == display.id
        }
        try checkLocation()
        var resolved = request
        var seenWindows: [String: ManagedWindow] = [:]
        var requestedPIDs: Set<pid_t> = []
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
            requestedPIDs.insert(pid)
            guard let session = manager.processSession(pid) else { throw Accessibility.NewWindowError.appClosed }
            var selected: [String] = []
            func candidates() async throws -> [ManagedWindow] {
                try await manager.refresh(for: [pid])
                let live = manager.windows.filter { $0.pid == pid }
                for window in live { seenWindows[window.id] = window }
                return live.filter { window in
                    if eligible(window) { return true }
                    // Creating a full-screen window can temporarily hide the original
                    // desktop from AX. Keep its exact bound windows in the count.
                    if indices.contains(where: { request.slots[$0].binding?.windowID == window.id }),
                       window.availability.document,
                       window.number.map({ Desktops.spaces(for: $0).contains(desktop.number) }) == true { return true }
                    guard let number = window.number, !initialNumbers.contains(number),
                          window.availability.document else { return false }
                    return window.availability.resizable || window.availability.fullScreen
                }
            }
            // Give a freshly launched application time to create its initial window.
            if !wasRunning {
                for _ in 0..<20 {
                    try checkLocation()
                    if try await !candidates().isEmpty { break }
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
            }
            do {
                selected = try await WindowCount.prepare(target: indices.count, current: {
                    try checkLocation()
                    let live = try await candidates()
                    let initialIDs = Set(initialNumbers.map { "\(pid):window-\($0)" })
                    for binding in indices.compactMap({ request.slots[$0].binding }) {
                        guard binding.processSession == session, live.contains(where: { $0.id == binding.windowID }) else {
                            throw GridLaunchError.windowMissing(choice.name)
                        }
                    }
                    return request.candidateIDs(bundleID: choice.bundleID, session: session,
                                                available: live.map(\.id), initial: initialIDs)
                }, requestNew: {
                    try checkLocation()
                    // Some apps publish New Window only while active. Their new windows may
                    // inherit full screen, which is handled below using exact WindowServer IDs.
                    if !app.isActive {
                        app.activate()
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                    try Task.checkCancellation()
                    if let item = try await Accessibility.perform({ Accessibility.newWindowCommand(pid: pid) }) {
                        guard try await Accessibility.perform({ AXUIElementPerformAction(item, kAXPressAction as CFString) }) == .success else {
                            throw Accessibility.NewWindowError.failed
                        }
                    } else if try await candidates().isEmpty, let url = app.bundleURL {
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = false
                        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    } else { throw Accessibility.NewWindowError.unavailable(choice.name) }
                }, wait: { try await Task.sleep(nanoseconds: 100_000_000) }, progress: { count in
                    progress("\(choice.name) · \(min(count, indices.count)) of \(indices.count) windows ready")
                }, pollsPerWindow: 100)
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
            // Only new windows can be entering an inherited full-screen Space.
            // Existing, eligible windows are ready to arrange immediately.
            let hasNewWindows = selected.contains { id in
                seenWindows[id]?.number.map { !initialNumbers.contains($0) } ?? true
            }
            if hasNewWindows {
                try await Task.sleep(nanoseconds: 900_000_000)
                _ = try await candidates()
            }
            var targets: [ManagedWindow] = []
            for id in selected {
                try checkLocation()
                guard let window = seenWindows[id] else { throw GridLaunchError.windowMissing(choice.name) }
                progress("Preparing \(choice.name) for this desktop…")
                manager.suppressUntil = Date().addingTimeInterval(30)
                if !window.availability.accessible || window.availability.fullScreen || window.availability.minimized {
                    _ = try await Accessibility.prepareForTiling(window, preserveFullScreen: false)
                    _ = try await candidates()
                }
                targets.append(seenWindows[id] ?? window)
            }
            try await Desktops.move(targets, to: desktop)
            if Desktops.current(displayID: display.id)?.number != desktop.number {
                try await Desktops.activate(desktop)
            }
        }
        try checkLocation()
        progress("Arranging your windows…")
        if Desktops.current(displayID: display.id)?.number != desktop.number {
            try await Desktops.activate(desktop)
        }
        // AX can lag the Space transition, especially for Electron windows.
        for _ in 0..<30 {
            try checkLocation()
            try await manager.refresh(for: requestedPIDs)
            let ids = resolved.slots.compactMap { $0.binding?.windowID }
            if ids.allSatisfy({ id in manager.windows.contains { $0.id == id && $0.availability.accessible && !$0.availability.fullScreen } }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // Frame calculation includes empty cells; they remain empty on the desktop too.
        guard let currentDisplay = Display.all.first(where: { $0.id == display.id }) else { throw GridLaunchError.changedDesktop }
        display = currentDisplay
        let frames = resolved.frames(in: display.bounds)
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
                guard try await Accessibility.perform({ AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }) == .success else {
                    throw GridLaunchError.windowMissing(choice.name)
                }
            }
            changes.append((window, frames[index]))
        }
        try checkLocation()
        try await manager.applyGrid(changes)
        // Verify on the worker. Already-settled apps finish immediately; Electron gets
        // the same bounded retry window without blocking input between observations.
        let placements = changes
        func unsettledWindows() async throws -> [(ManagedWindow, CGRect)] {
            try await Accessibility.perform {
                placements.filter { window, target in
                    guard let actual = Accessibility.rect(window.element) else { return true }
                    return !Geometry.approximatelyEqual(actual, target, tolerance: 6)
                }
            }
        }
        // New AppKit windows may ignore a resize during their opening animation.
        // Retry only outstanding placements; already-settled layouts never sleep.
        let unsettled = try await WindowSettling.finish(pending: unsettledWindows, retry: { window, target in
            _ = try await Accessibility.perform { Accessibility.move(window, to: target) }
        }, wait: { try await Task.sleep(nanoseconds: 150_000_000) })
        // Removing a pane or replacing its app presses its window's close button (save dialogs stay native).
        // Windows displaced by other layout edits are minimized instead.
        let retained = Set(resolved.slots.compactMap { $0.binding?.windowID })
        for slot in original?.slots ?? [] {
            guard let binding = slot.binding, !retained.contains(binding.windowID), let choice = slot.app,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: choice.bundleID).first,
                  manager.processSession(app.processIdentifier) == binding.processSession else { continue }
            try Task.checkCancellation()
            let live = try await Accessibility.windows(for: [app.processIdentifier])
            guard let window = live.first(where: { $0.id == binding.windowID }) else { continue }
            // Never act on a pane moved to another desktop since the overlay opened.
            guard window.number.map({ Desktops.spaces(for: $0).contains(desktop.number) }) == true else { continue }
            let shouldClose = request.windowsToClose?.contains(binding) == true
            let accepted = try await Accessibility.perform {
                if shouldClose {
                    guard let button = Accessibility.value(window.element, kAXCloseButtonAttribute),
                          CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
                    return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
                }
                return AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
            }
            if !accepted { throw GridLaunchError.windowMissing(choice.name) }
        }
        resolved.windowsToClose = nil
        let constrained = unsettled.count
        return GridLaunchResult(grid: resolved, exact: constrained == 0,
            message: "\(constrained) window\(constrained == 1 ? " has" : "s have") a minimum size or couldn’t be moved. Try fewer rows or columns.")
    }
}
