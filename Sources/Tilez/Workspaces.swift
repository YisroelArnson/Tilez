import AppKit
import ApplicationServices
import TilezCore

enum WorkspaceError: LocalizedError {
    case closed(String), disconnected(String), nothingToSave, noneShown, fullScreen(String)
    var errorDescription: String? {
        switch self {
        case .closed(let name): return "All of “\(name)”’s windows have closed, so it’s gone."
        case .disconnected(let name): return "None of the screens “\(name)” was saved on are connected."
        case .nothingToSave: return "There are no windows on this screen to save."
        case .noneShown: return "This screen isn’t showing a workspace. Save it as a new one."
        case .fullScreen(let screen): return "\(screen) is showing a full-screen app. Leave full screen there and try again."
        }
    }
}

/// Saved workspaces and which one each screen shows. Windows that have closed are dropped
/// whenever a workspace is read, so it never refers to a window that isn't there.
@MainActor final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    private(set) var shown = ShownWorkspaces()
    let manager: WindowManager
    private let defaults: UserDefaults
    private static let workspacesKey = "workspacesV1", shownKey = "shownWorkspacesV1"

    init(manager: WindowManager, defaults: UserDefaults = .standard) {
        self.manager = manager; self.defaults = defaults
        workspaces = defaults.data(forKey: Self.workspacesKey)
            .flatMap { try? JSONDecoder().decode([Workspace].self, from: $0) }?
            .filter { $0.screens.allSatisfy { $0.grid.isValid } } ?? []
        shown = defaults.data(forKey: Self.shownKey).flatMap { try? JSONDecoder().decode(ShownWorkspaces.self, from: $0) } ?? ShownWorkspaces()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(workspaces), forKey: Self.workspacesKey)
        defaults.set(try? JSONEncoder().encode(shown), forKey: Self.shownKey)
    }

    private func store(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) { workspaces[index] = workspace }
        else { workspaces.append(workspace) }
        persist()
    }

    /// A default name that won't replace an existing workspace.
    var suggestedName: String {
        let names = Set(workspaces.map { $0.name.lowercased() })
        return (1...).lazy.map { "Workspace \($0)" }.first { !names.contains($0.lowercased()) }!
    }

    func remove(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        shown.forget(id)
        persist()
    }

    /// Every workspace, without windows that have closed.
    func current() -> [Workspace] {
        let open = openWindowIDs()
        for workspace in workspaces { prune(workspace, open: open) }
        return workspaces
    }

    /// The workspace this screen shows on its current desktop, without windows that have closed.
    func shownWorkspace(on display: Display) -> Workspace? {
        guard let desktop = Desktops.current(displayID: display.id),
              let id = shown.workspace(on: display.id, desktop: desktop.id),
              let workspace = workspaces.first(where: { $0.id == id }) else { return nil }
        return prune(workspace, open: openWindowIDs())
    }

    @discardableResult private func prune(_ workspace: Workspace, open: Set<String>) -> Workspace? {
        let kept = workspace.keeping { binding in
            open.contains(binding.windowID) && pid(binding).flatMap { manager.processSession($0) } == binding.processSession
        }
        guard kept != workspace else { return workspace }
        if let kept { store(kept) } else { remove(workspace.id) }
        return kept
    }

    private func pid(_ binding: GridWindowBinding) -> pid_t? {
        binding.windowID.split(separator: ":").first.flatMap { Int32($0) }
    }

    /// WindowServer keeps a closed window's number only while the app retains it off every desktop.
    /// Minimized windows and windows on other desktops still belong to a desktop.
    private func openWindowIDs() -> Set<String> {
        let wanted = Set(workspaces.flatMap(\.bindings).map(\.windowID))
        let records = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(records.compactMap { record -> String? in
            guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let number = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
            let id = "\(pid):window-\(number)"
            return wanted.contains(id) && !Desktops.spaces(for: number).isEmpty ? id : nil
        })
    }

    /// Brings the workspace's own windows here and arranges them. It never opens a window, and
    /// other windows on these screens stay where they are.
    func open(_ listed: Workspace, from display: Display, progress: @escaping (String) -> Void) async throws {
        guard Accessibility.trusted else { Accessibility.requestPermission(); throw Accessibility.NewWindowError.failed }
        guard let requested = workspaces.first(where: { $0.id == listed.id }) else { throw WorkspaceError.closed(listed.name) }
        let pids = Set(requested.bindings.compactMap(pid))
        try await manager.refresh(for: pids)
        let live = Set(manager.windows.map(\.id))
        let open = openWindowIDs().intersection(live)
        guard let workspace = prune(requested, open: open) else { throw WorkspaceError.closed(requested.name) }
        // The screen you're on goes last, so its windows end up in front.
        let destinations = workspace.destinations(connected: Display.all.map(\.id), current: display.id)
            .sorted { $0.displayID != display.id && $1.displayID == display.id }
        guard !destinations.isEmpty else { throw WorkspaceError.disconnected(workspace.name) }
        for destination in destinations {
            guard let target = Display.all.first(where: { $0.id == destination.displayID }),
                  Desktops.current(displayID: target.id, includeFullScreen: true)?.isFullScreen != true else {
                throw WorkspaceError.fullScreen(Display.all.first { $0.id == destination.displayID }?.name ?? "A screen")
            }
        }
        // Pull windows off other desktops through WindowServer first. Otherwise the launcher
        // switches to each of their desktops to reach them.
        for destination in destinations {
            guard Desktops.canMove, let desktop = Desktops.current(displayID: destination.displayID) else { continue }
            let ids = Set(destination.screen.grid.slots.compactMap { $0.binding?.windowID })
            let away = manager.windows.filter { window in
                ids.contains(window.id) && !window.availability.accessible && !window.availability.fullScreen
                    && window.number.map { !Desktops.spaces(for: $0).contains(desktop.number) } == true
            }
            if !away.isEmpty { try? await Desktops.move(away, to: desktop) }
        }
        shown.forget(workspace.id)
        for destination in destinations {
            guard let target = Display.all.first(where: { $0.id == destination.displayID }),
                  let desktop = Desktops.current(displayID: target.id, includeFullScreen: true) else { throw DesktopError.unavailable }
            // A window with a minimum size can't match its pane exactly; the workspace still opens.
            _ = try await GridLauncher.open(destination.screen.grid, display: target, desktop: desktop, manager: manager,
                                            gathering: true, progress: progress, prepared: { _, _ in })
            shown.show(workspace.id, on: target.id, desktop: desktop.id)
            persist()
        }
        await bringForward(destinations.flatMap { $0.screen.grid.slots.compactMap { $0.binding?.windowID } })
    }

    /// Placing a window only raises it within its app. Activate each app from back to front so
    /// the workspace sits above other windows, with the first pane's app active.
    private func bringForward(_ ids: [String]) async {
        let windows = ids.compactMap { id in manager.windows.first { $0.id == id } }
        var order: [pid_t] = []
        for window in windows where !order.contains(window.pid) { order.append(window.pid) }
        for pid in order.reversed() {
            NSRunningApplication(processIdentifier: pid)?.activate()
            for window in windows.reversed() where window.pid == pid {
                _ = try? await Accessibility.perform { AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) }
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    /// Saves the workspace this screen shows, from every screen still showing it.
    func saveShown(on display: Display) async throws -> Workspace {
        guard let workspace = shownWorkspace(on: display) else { throw WorkspaceError.noneShown }
        var next: Workspace? = workspace
        for screen in Display.all {
            guard let desktop = Desktops.current(displayID: screen.id),
                  shown.workspace(on: screen.id, desktop: desktop.id) == workspace.id,
                  let grid = try await capture(screen) else { continue }
            next = next?.saving(grid, on: screen.id)
        }
        guard let next else { throw WorkspaceError.nothingToSave }
        store(next)
        return next
    }

    /// A new workspace from what this screen, or every screen, shows now. A workspace with the
    /// same name is replaced, like saving over a file.
    func saveNew(named name: String, allScreens: Bool, from display: Display) async throws -> Workspace {
        let screens = allScreens ? [display] + Display.all.filter { $0.id != display.id } : [display]
        var captured: [(WorkspaceScreen, String)] = []
        for screen in screens {
            guard let grid = try await capture(screen), let desktop = Desktops.current(displayID: screen.id),
                  let arranged = WorkspaceScreen(displayID: screen.id, arranging: grid) else { continue }
            captured.append((arranged, desktop.id))
        }
        guard !captured.isEmpty else { throw WorkspaceError.nothingToSave }
        let existing = workspaces.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        let workspace = Workspace(id: existing?.id ?? UUID(), name: name, screens: captured.map(\.0))
        store(workspace)
        shown.forget(workspace.id)
        for (screen, desktop) in captured { shown.show(workspace.id, on: screen.displayID, desktop: desktop) }
        persist()
        return workspace
    }

    /// Full-screen desktops hold one app's window, not an arrangement.
    private func capture(_ display: Display) async throws -> DesktopGrid? {
        guard let desktop = Desktops.current(displayID: display.id, includeFullScreen: true), !desktop.isFullScreen else { return nil }
        return try await GridEditorModel.visibleDesktop(display: display, desktop: desktop, manager: manager)
    }

    /// Quick Add's new window joins the workspace this screen shows.
    func join(_ window: GridWindowBinding, arranged: DesktopGrid, on display: Display) {
        guard let workspace = shownWorkspace(on: display) else { return }
        store(workspace.joining(window, arranged: arranged, on: display.id))
    }

    func layoutOpened(on display: Display) {
        shown.clear(display.id)
        persist()
    }
}
