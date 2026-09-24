import Foundation
import CoreGraphics

/// Open windows kept in one arrangement, on one screen or several. A workspace never opens a
/// window: one that closes leaves it for good, and a neighboring pane grows into its space.
/// A saved layout is the opposite: apps only, and opening it always opens new windows.
public struct Workspace: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public private(set) var screens: [WorkspaceScreen]

    public init(id: UUID = UUID(), name: String, screens: [WorkspaceScreen]) {
        self.id = id; self.name = name
        self.screens = screens.compactMap { WorkspaceScreen(displayID: $0.displayID, arranging: $0.grid) }
    }

    public var bindings: [GridWindowBinding] { screens.flatMap { $0.grid.slots.compactMap(\.binding) } }
    public var windowCount: Int { bindings.count }

    /// A one-screen workspace belongs to whichever screen shows it.
    public func screen(on displayID: String) -> WorkspaceScreen? {
        screens.count == 1 ? screens.first : screens.first { $0.displayID == displayID }
    }

    /// Without the windows that have closed; nil once none remain.
    public func keeping(_ isOpen: (GridWindowBinding) -> Bool) -> Workspace? {
        var next = self
        next.screens = screens.compactMap { screen in
            var grid = screen.grid
            for index in grid.slots.indices.reversed() where !(grid.slots[index].binding.map(isOpen) ?? false) {
                if grid.slots.count == 1 { return nil }
                grid.removePane(index)
            }
            return WorkspaceScreen(displayID: screen.displayID, arranging: grid)
        }
        return next.screens.isEmpty ? nil : next
    }

    /// A one-screen workspace comes to the screen you're on. A multi-screen workspace returns to
    /// each of its screens that is connected; a disconnected screen's windows stay where they are.
    public func destinations(connected: [String], current: String) -> [(screen: WorkspaceScreen, displayID: String)] {
        if screens.count == 1 { return [(screens[0], current)] }
        return screens.filter { connected.contains($0.displayID) }.map { ($0, $0.displayID) }
    }

    /// A screen showing a full-screen app shows the workspace on one of its regular desktops
    /// instead, leaving the app in full screen: the desktop it last showed this workspace on, else
    /// the one holding most of the workspace's windows for that screen, else its first desktop.
    public static func regularDesktop(among desktops: [String], lastShown: String?, windows: [String: Int]) -> String? {
        if let lastShown, desktops.contains(lastShown) { return lastShown }
        let most = desktops.max { (windows[$0] ?? 0) < (windows[$1] ?? 0) }
        return most.flatMap { (windows[$0] ?? 0) > 0 ? $0 : nil } ?? desktops.first
    }

    /// Saving takes a screen's windows and arrangement as they are now. An empty screen leaves
    /// the workspace; nil when no screen has windows left.
    public func saving(_ grid: DesktopGrid, on displayID: String) -> Workspace? {
        var next = self
        let replaced = screens.count == 1 ? 0 : screens.firstIndex { $0.displayID == displayID }
        if let replaced { next.screens.remove(at: replaced) }
        if let screen = WorkspaceScreen(displayID: displayID, arranging: grid) {
            next.screens.insert(screen, at: min(replaced ?? next.screens.count, next.screens.count))
        }
        return next.screens.isEmpty ? nil : next
    }

    /// Quick Add's window joins. When all of the screen's windows are in `arranged`, the workspace
    /// takes on the arrangement that made room for it; other windows there stay out. When some are
    /// elsewhere (minimized, or on another desktop), the workspace makes room in its own arrangement
    /// the way Quick Add does: the largest pane splits along its longer side.
    public func joining(_ window: GridWindowBinding, arranged: DesktopGrid, on displayID: String) -> Workspace {
        guard let added = arranged.slots.first(where: { $0.binding == window }) else { return self }
        let current = screen(on: displayID)
        let members = current?.grid.slots.compactMap(\.binding) ?? []
        let present = Set(arranged.slots.compactMap(\.binding))
        var grid: DesktopGrid
        if members.allSatisfy(present.contains) {
            let frames = arranged.normalizedFrames
            let kept = arranged.slots.indices.filter { arranged.slots[$0].binding.map { members.contains($0) || $0 == window } == true }
            grid = DesktopGrid(panes: kept.map { arranged.slots[$0] }, frames: kept.map { frames[$0] })
        } else if var own = current?.grid {
            let frames = own.normalizedFrames
            let largest = frames.indices.max { frames[$0].width * frames[$0].height < frames[$1].width * frames[$1].height }!
            guard let index = own.split(largest, toward: frames[largest].width >= frames[largest].height ? .right : .bottom) else { return self }
            own.slots[index] = added
            grid = own
        } else {
            grid = DesktopGrid(panes: [added], frames: [CGRect(x: 0, y: 0, width: 1, height: 1)])
        }
        return saving(grid, on: displayID) ?? self
    }

    /// True when the screen shows anything besides this workspace's windows exactly where it
    /// keeps them, so saving would change it.
    public func isModified(on displayID: String, showing grid: DesktopGrid, tolerance: CGFloat = 0.01) -> Bool {
        guard let screen = screen(on: displayID) else { return true }
        let shown = grid.normalizedFrames
        let showing = Dictionary(grid.slots.indices.compactMap { index in
            grid.slots[index].binding.map { ($0, shown[index]) }
        }, uniquingKeysWith: { first, _ in first })
        let kept = screen.grid.normalizedFrames
        guard showing.count == screen.grid.slots.count else { return true }
        return screen.grid.slots.indices.contains { index in
            guard let binding = screen.grid.slots[index].binding, let frame = showing[binding] else { return true }
            let expected = kept[index]
            return abs(frame.minX - expected.minX) > tolerance || abs(frame.minY - expected.minY) > tolerance
                || abs(frame.maxX - expected.maxX) > tolerance || abs(frame.maxY - expected.maxY) > tolerance
        }
    }
}

public struct WorkspaceScreen: Codable, Equatable {
    public var displayID: String
    /// Every pane holds one of the workspace's windows, at its exact normalized frame.
    public var grid: DesktopGrid

    /// Keeps only panes bound to a window; nil when there are none.
    public init?(displayID: String, arranging grid: DesktopGrid) {
        let frames = grid.normalizedFrames
        let bound = grid.slots.indices.filter { grid.slots[$0].app != nil && grid.slots[$0].binding != nil }
        guard !bound.isEmpty else { return nil }
        self.displayID = displayID
        self.grid = DesktopGrid(panes: bound.map { GridSlot(app: grid.slots[$0].app, binding: grid.slots[$0].binding, title: grid.slots[$0].title) },
                                frames: bound.map { frames[$0] })
    }
}

/// Which workspace each screen is showing: the one last opened or saved on that screen's
/// current desktop, until a different workspace or a saved layout opens there. Moving its windows
/// only makes it modified; it never quietly stops being shown.
public struct ShownWorkspaces: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var workspace: UUID
        public var desktop: String
    }
    public private(set) var screens: [String: Entry] = [:]
    public init() {}

    public mutating func show(_ workspace: UUID, on displayID: String, desktop: String) {
        screens[displayID] = Entry(workspace: workspace, desktop: desktop)
    }
    public mutating func clear(_ displayID: String) { screens.removeValue(forKey: displayID) }
    public mutating func forget(_ workspace: UUID) { screens = screens.filter { $0.value.workspace != workspace } }
    public func workspace(on displayID: String, desktop: String) -> UUID? {
        screens[displayID].flatMap { $0.desktop == desktop ? $0.workspace : nil }
    }
    public func displays(showing workspace: UUID) -> [String] {
        screens.filter { $0.value.workspace == workspace }.map(\.key).sorted()
    }
}
