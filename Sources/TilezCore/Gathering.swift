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
    }
    /// Front to back, per display ID.
    public private(set) var screens: [String: [Window]] = [:]
    public init() {}

    /// What a screen shows now replaces what it showed before, and its windows leave every other
    /// screen's record. `grid` holds the screen's windows front to back at their exact frames.
    public mutating func record(_ grid: DesktopGrid, on displayID: String) {
        let frames = grid.normalizedFrames
        let windows = grid.slots.indices.compactMap { index -> Window? in
            guard grid.slots[index].app != nil, grid.slots[index].binding != nil else { return nil }
            return Window(slot: grid.slots[index], frame: frames[index])
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
        let away = (screens[displayID] ?? []).filter { window in
            guard let binding = window.slot.binding, let now = location(binding) else { return false }
            return now != displayID
        }
        guard !away.isEmpty else { return nil }
        return DesktopGrid(panes: away.map(\.slot), frames: away.map(\.frame))
    }
}
