import AppKit
import TilezCore

extension Desktops {
    /// ⌃⌥X: closes every desktop without windows, except the one each screen shows. Returns how
    /// many closed.
    @MainActor static func closeEmpty(returningTo display: Display) async throws -> Int {
        guard canMove else { throw DesktopError.unavailable }
        let desktops = all()
        let counts = windowCounts()
        let closable = Set(DesktopPlan.closable(desktops.map {
            DesktopPlan.Desktop(id: $0.id, displayID: $0.displayID, isCurrent: $0.isCurrent, windows: counts[$0.number] ?? 0)
        }))
        let closing = desktops.filter { closable.contains($0.id) }
        guard !closing.isEmpty, let current = current(displayID: display.id, includeFullScreen: true) else { return 0 }
        try await close(closing, returningTo: current)
        return closing.count
    }
}

extension WorkspaceStore {
    /// ⌃⌥D: gives every workspace a desktop of its own and opens it there. Each keeps the desktop
    /// holding most of its windows, else takes an empty one, else a new one. A one-screen
    /// workspace goes to this screen, as when it opens. Other windows stay where they are. You end
    /// on the workspace this screen showed, else the desktops you were on. Returns how many
    /// workspaces were placed.
    func spread(from display: Display) async throws -> Int {
        guard Accessibility.trusted else { Accessibility.requestPermission(); throw Accessibility.NewWindowError.failed }
        guard Desktops.canMove else { throw DesktopError.unavailable }
        let live = current()
        guard !live.isEmpty else { throw WorkspaceError.noneSaved }
        let connected = Display.all.map(\.id)
        let destinations = live.map { $0.destinations(connected: connected, current: display.id) }
        let desktops = Desktops.all()
        let counts = Desktops.windowCounts()
        var landing = Desktops.all(includeFullScreen: true).filter(\.isCurrent)
        let wasShown = shownWorkspace(on: display)?.id

        // Plan each screen on its own: which desktop each workspace using it gets there.
        var homes: [Int: [String: String?]] = [:]
        for screen in Set(destinations.flatMap { $0.map(\.displayID) }) {
            let mine = desktops.filter { $0.displayID == screen }
            let using = live.indices.filter { index in destinations[index].contains { $0.displayID == screen } }
            let windows = using.map { index -> [String: Int] in
                let ids = destinations[index].first { $0.displayID == screen }!.screen.grid.slots.compactMap { $0.binding?.windowID }
                var found: [String: Int] = [:]
                for id in ids {
                    guard let number = id.split(separator: "-").last.flatMap({ UInt32($0) }) else { continue }
                    let spaces = Desktops.spaces(for: number)
                    for desktop in mine where spaces.contains(desktop.number) { found[desktop.id, default: 0] += 1 }
                }
                return found
            }
            let planned = DesktopPlan.homes(for: windows, desktops: mine.map(\.id),
                                            empty: Set(mine.filter { (counts[$0.number] ?? 0) == 0 }.map(\.id)))
            for (index, home) in zip(using, planned) { homes[index, default: [:]][screen] = home }
        }

        for (index, workspace) in live.enumerated() {
            for destination in destinations[index] {
                guard let target = Display.all.first(where: { $0.id == destination.displayID }) else { continue }
                if let id = homes[index]?[destination.displayID] ?? nil, let desktop = Desktops.all().first(where: { $0.id == id }) {
                    try await Desktops.activate(desktop)
                } else {
                    _ = try await Desktops.create(on: target)
                }
            }
            try await open(workspace, from: display, progress: { _ in })
            if workspace.id == wasShown {
                landing = destinations[index].compactMap { Desktops.current(displayID: $0.displayID) }
            }
        }
        for desktop in landing where Desktops.all(includeFullScreen: true).contains(where: { $0.number == desktop.number }) {
            try? await Desktops.activate(desktop)
        }
        return live.count
    }
}
