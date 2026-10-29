import Foundation
import CoreGraphics

extension DesktopGrid {
    /// The most panes an even tiling holds: a full 6 × 4 grid.
    public static var maxTiled: Int { maxColumns * maxRows }

    /// Panes in an even grid, in the order given, left to right and top to bottom. A short last
    /// row stretches its panes across the screen rather than leaving a hole. Panes past
    /// `maxTiled` are left out.
    public static func tiling(_ panes: [GridSlot], aspect: CGFloat, gap: CGSize = CGSize(width: 0.008, height: 0.008)) -> DesktopGrid {
        let panes = Array(panes.prefix(maxTiled))
        guard !panes.isEmpty else { return .emptyDesktop }
        let shape = tilingShape(count: panes.count, aspect: aspect)
        let height = (1 - CGFloat(shape.rows - 1) * gap.height) / CGFloat(shape.rows)
        var frames: [CGRect] = []
        for row in 0..<shape.rows {
            let count = min(shape.columns, panes.count - row * shape.columns)
            let width = (1 - CGFloat(count - 1) * gap.width) / CGFloat(count)
            for column in 0..<count {
                frames.append(CGRect(x: CGFloat(column) * (width + gap.width), y: CGFloat(row) * (height + gap.height),
                                     width: width, height: height))
            }
        }
        return DesktopGrid(panes: panes, frames: frames)
    }

    /// Columns and rows that keep each pane about as wide as it is tall on a screen of `aspect`
    /// (width over height), with as few short-row gaps as possible.
    public static func tilingShape(count: Int, aspect: CGFloat) -> (columns: Int, rows: Int) {
        let count = max(1, min(maxTiled, count))
        var best = (columns: 1, rows: 1), bestScore = CGFloat.infinity
        for columns in 1...min(maxColumns, count) {
            let rows = (count + columns - 1) / columns
            guard rows <= maxRows else { continue }
            let paneAspect = max(aspect, 0.01) * CGFloat(rows) / CGFloat(columns)
            let score = abs(log(paneAspect)) + 0.3 * CGFloat(columns * rows - count)
            if score < bestScore { best = (columns, rows); bestScore = score }
        }
        return best
    }

    /// Pane indices top to bottom, then left to right. Panes whose tops are close count as one
    /// row; panes in the same spot keep their order.
    public var readingOrder: [Int] {
        let frames = normalizedFrames
        return frames.indices.sorted { a, b in
            let rowA = Int((frames[a].minY / 0.1).rounded()), rowB = Int((frames[b].minY / 0.1).rounded())
            if rowA != rowB { return rowA < rowB }
            if abs(frames[a].minX - frames[b].minX) > 0.001 { return frames[a].minX < frames[b].minX }
            return a < b
        }
    }
}

/// Where each window sat on each screen, so windows macOS moves off a screen that disconnects
/// can go back when it returns. A window belongs to the last screen that recorded it. Screens
/// are recorded only while more than one is connected, so the windows that pile onto the
/// laptop while it's on its own still belong to the monitor they came from.
public struct ScreenMemory: Codable, Equatable {
    public struct Window: Codable, Equatable {
        public var slot: GridSlot
        /// Normalized within the screen's usable area.
        public var frame: CGRect
        /// The original Space UUID (or its session ID on systems without a UUID).
        /// Nil in records written before desktop grouping, and for windows on several Spaces.
        public var desktop: String?
    }
    /// Front to back, per display ID.
    public private(set) var screens: [String: [Window]] = [:]
    /// Replacement Space identities survive retries and app restarts while a monitor is away.
    private var replacements: [String: String]?
    public init() {}

    /// What a screen shows now replaces what it showed before, and its windows leave every other
    /// screen's record. `grid` holds the screen's windows front to back at their exact frames.
    public mutating func record(_ grid: DesktopGrid, on displayID: String, desktops: [GridWindowBinding: String] = [:]) {
        let frames = grid.normalizedFrames
        let windows = grid.slots.indices.compactMap { index -> Window? in
            guard grid.slots[index].app != nil, grid.slots[index].binding != nil else { return nil }
            return Window(slot: grid.slots[index], frame: frames[index], desktop: grid.slots[index].binding.flatMap { desktops[$0] })
        }
        let ids = Set(windows.compactMap { $0.slot.binding?.windowID })
        for (other, kept) in screens where other != displayID {
            let remaining = kept.filter { !ids.contains($0.slot.binding?.windowID ?? "") }
            screens[other] = remaining.isEmpty ? nil : remaining
        }
        screens[displayID] = windows.isEmpty ? nil : windows
    }

    /// Windows that have closed are forgotten.
    public mutating func keep(_ isOpen: (GridWindowBinding) -> Bool) {
        for (displayID, windows) in screens {
            let open = windows.filter { $0.slot.binding.map(isOpen) ?? false }
            screens[displayID] = open.isEmpty ? nil : open
        }
    }

    /// The windows remembered on `displayID` that are now on a different screen, at their
    /// remembered frames. `location` gives the screen a window is on now, or nil when it can't
    /// be moved back (closed, minimized, or its app is hidden). Nil when none are away.
    public func displaced(from displayID: String, location: (GridWindowBinding) -> String?) -> DesktopGrid? {
        displaced(from: displayID, whereabouts: { binding in location(binding).map { Whereabouts(displayID: $0) } })
    }

    /// Where a window is now: its screen, and when known, its only desktop and its frame
    /// normalized within that screen's usable area.
    public struct Whereabouts: Equatable {
        public var displayID: String
        public var desktop: String?
        public var frame: CGRect?
        public init(displayID: String, desktop: String? = nil, frame: CGRect? = nil) {
            self.displayID = displayID; self.desktop = desktop; self.frame = frame
        }
    }

    /// Like `displaced(from:location:)`, but a window macOS already returned to its screen still
    /// needs putting back when it's on another desktop than its own (or that desktop's
    /// replacement), or away from its remembered frame.
    public func displaced(from displayID: String, whereabouts: (GridWindowBinding) -> Whereabouts?) -> DesktopGrid? {
        let away = (screens[displayID] ?? []).filter { window in
            guard let binding = window.slot.binding, let now = whereabouts(binding) else { return false }
            if now.displayID != displayID { return true }
            if let desktop = window.desktop, let current = now.desktop, current != desktop,
               current != replacements?["\(displayID)|\(displayID)|\(desktop)"] { return true }
            if let frame = now.frame, !Self.isAt(frame, window.frame) { return true }
            return false
        }
        guard !away.isEmpty else { return nil }
        return DesktopGrid(panes: away.map(\.slot), frames: away.map(\.frame))
    }

    /// True when a normalized frame is where one was remembered, give or take a window that
    /// couldn't quite reach its size.
    public static func isAt(_ frame: CGRect, _ remembered: CGRect, tolerance: CGFloat = 0.02) -> Bool {
        abs(frame.minX - remembered.minX) <= tolerance && abs(frame.minY - remembered.minY) <= tolerance
            && abs(frame.maxX - remembered.maxX) <= tolerance && abs(frame.maxY - remembered.maxY) <= tolerance
    }

    public struct DesktopGroup {
        public let displayID: String
        public let desktop: String
        public let grid: DesktopGrid
    }

    public func replacement(for group: DesktopGroup, on displayID: String) -> String? {
        replacements?["\(displayID)|\(group.displayID)|\(group.desktop)"]
    }

    public mutating func rememberReplacement(_ desktop: String, for group: DesktopGroup, on displayID: String) {
        if replacements == nil { replacements = [:] }
        replacements?["\(displayID)|\(group.displayID)|\(group.desktop)"] = desktop
    }

    /// Each original desktop stays a separate group, even when macOS piles its windows onto
    /// the same surviving desktop. Only exact, still-movable window bindings are included.
    /// Legacy records and windows assigned to several Spaces have no unambiguous group.
    public func desktopGroups(on displayIDs: Set<String>, keeping movable: Set<GridWindowBinding>) -> [DesktopGroup] {
        var result: [DesktopGroup] = []
        for displayID in displayIDs.sorted() {
            var order: [String] = []
            var groups: [String: [Window]] = [:]
            for window in screens[displayID] ?? [] {
                guard let desktop = window.desktop, let binding = window.slot.binding, movable.contains(binding) else { continue }
                if groups[desktop] == nil { order.append(desktop) }
                groups[desktop, default: []].append(window)
            }
            for desktop in order {
                let windows = groups[desktop]!
                result.append(DesktopGroup(displayID: displayID, desktop: desktop,
                    grid: DesktopGrid(panes: windows.map(\.slot), frames: windows.map(\.frame))))
            }
        }
        return result
    }
}
