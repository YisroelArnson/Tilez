import Foundation

public struct GridApp: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
}

/// A binding identifies one live window, including the process launch that owns it.
public struct GridWindowBinding: Codable, Equatable {
    public var windowID: String
    public var processSession: String
    public init(windowID: String, processSession: String) {
        self.windowID = windowID; self.processSession = processSession
    }
}

public struct GridSlot: Codable, Equatable {
    public var app: GridApp?
    public var binding: GridWindowBinding?
    public var opensNewWindow: Bool?
    public var title: String?
    public init(app: GridApp? = nil, binding: GridWindowBinding? = nil, opensNewWindow: Bool? = nil, title: String? = nil) {
        self.app = app; self.binding = binding
        self.opensNewWindow = opensNewWindow; self.title = title
    }
}

/// Row-major cells, including intentional holes. Empty cells never collapse the layout.
public struct DesktopGrid: Codable, Equatable {
    public static let maxColumns = 6
    public static let maxRows = 4
    public private(set) var columns: Int
    public private(set) var rows: Int
    public var slots: [GridSlot]
    public var windowsToClose: [GridWindowBinding]?
    /// Exact normalized pane bounds. Nil keeps legacy equal-grid templates compatible.
    public internal(set) var paneFrames: [CGRect]?

    public init(columns: Int = 2, rows: Int = 2, slots: [GridSlot] = []) {
        self.columns = min(Self.maxColumns, max(1, columns))
        self.rows = min(Self.maxRows, max(1, rows))
        self.slots = Array(slots.prefix(self.columns * self.rows))
        self.slots += Array(repeating: GridSlot(), count: self.columns * self.rows - self.slots.count)
    }
    public var isValid: Bool {
        if let paneFrames {
            return !slots.isEmpty && paneFrames.count == slots.count
                && paneFrames.allSatisfy { $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite
                    && $0.width > 0 && $0.height > 0 && $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 1.001 && $0.maxY <= 1.001 }
                && slots.allSatisfy { $0.app.map { !$0.bundleID.isEmpty } ?? ($0.binding == nil) }
        }
        return         (1...Self.maxColumns).contains(columns) && (1...Self.maxRows).contains(rows)
            && slots.count == columns * rows
            && slots.allSatisfy { $0.app.map { !$0.bundleID.isEmpty } ?? ($0.binding == nil) }
    }
    public var filledCount: Int { slots.filter { $0.app != nil }.count }
    public var template: DesktopGrid {
        var copy = self
        copy.slots = slots.map { GridSlot(app: $0.app) }
        copy.windowsToClose = nil
        return copy
    }

    public mutating func resize(columns: Int, rows: Int) {
        var next = DesktopGrid(columns: columns, rows: rows)
        next.windowsToClose = windowsToClose
        if paneFrames != nil {
            // Explicitly choosing a grid evenly redistributes the current panes.
            for index in 0..<min(slots.count, next.slots.count) { next.slots[index] = slots[index] }
            self = next
            return
        }
        for row in 0..<min(self.rows, next.rows) {
            for column in 0..<min(self.columns, next.columns) {
                next.slots[row * next.columns + column] = slots[row * self.columns + column]
            }
        }
        self = next
    }

    public mutating func move(from source: Int, to destination: Int, repeating: Bool) {
        guard slots.indices.contains(source), slots.indices.contains(destination), source != destination else { return }
        if repeating {
            guard let app = slots[source].app else { return }
            // Repeating an app must never bind two cells to the same live window.
            slots[destination] = GridSlot(app: app, opensNewWindow: true)
        } else { slots.swapAt(source, destination) }
    }

    /// Grow only when no empty cell remains, preserving each existing cell's position.
    public mutating func makeRoom() -> Int? {
        if let empty = slots.firstIndex(where: { $0.app == nil }) { return empty }
        if columns <= rows && columns < Self.maxColumns { resize(columns: columns + 1, rows: rows) }
        else if rows < Self.maxRows { resize(columns: columns, rows: rows + 1) }
        else if columns < Self.maxColumns { resize(columns: columns + 1, rows: rows) }
        return slots.firstIndex { $0.app == nil }
    }
}

public struct SavedGrid: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var grid: DesktopGrid
    public init(id: UUID = UUID(), name: String, grid: DesktopGrid) {
        self.id = id; self.name = name; self.grid = grid.template
    }
}
