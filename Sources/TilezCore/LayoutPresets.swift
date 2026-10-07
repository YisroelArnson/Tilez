import Foundation
import CoreGraphics

/// A ready-made arrangement of panes, edge to edge in unit space. Gaps are added when it's used.
public struct LayoutPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let frames: [CGRect]

    public init(id: String, name: String, frames: [CGRect]) {
        self.id = id; self.name = name; self.frames = frames
    }

    public static let all: [LayoutPreset] = {
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
        let third: CGFloat = 1 / 3
        return [
            LayoutPreset(id: "full", name: "One window", frames: [r(0, 0, 1, 1)]),
            LayoutPreset(id: "halves", name: "Side by side", frames: [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 1)]),
            LayoutPreset(id: "stacked", name: "Stacked", frames: [r(0, 0, 1, 0.5), r(0, 0.5, 1, 0.5)]),
            LayoutPreset(id: "thirds", name: "Three tall", frames: [r(0, 0, third, 1), r(third, 0, third, 1), r(2 * third, 0, third, 1)]),
            LayoutPreset(id: "wide-middle", name: "Wide middle", frames: [r(0, 0, 0.25, 1), r(0.25, 0, 0.5, 1), r(0.75, 0, 0.25, 1)]),
            LayoutPreset(id: "main-left", name: "Main and two stacked",
                         frames: [r(0, 0, 0.5, 1), r(0.5, 0, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]),
            LayoutPreset(id: "main-right", name: "Two stacked and main",
                         frames: [r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 1), r(0, 0.5, 0.5, 0.5)]),
            LayoutPreset(id: "quarters", name: "Four", frames: [r(0, 0, 0.5, 0.5), r(0.5, 0, 0.5, 0.5), r(0, 0.5, 0.5, 0.5), r(0.5, 0.5, 0.5, 0.5)]),
            LayoutPreset(id: "main-three", name: "Main and three stacked",
                         frames: [r(0, 0, 0.6, 1), r(0.6, 0, 0.4, third), r(0.6, third, 0.4, third), r(0.6, 2 * third, 0.4, third)]),
            LayoutPreset(id: "tall-middle", name: "Tall middle, stacked sides",
                         frames: [r(0, 0, 0.3, 0.5), r(0.3, 0, 0.4, 1), r(0.7, 0, 0.3, 0.5), r(0, 0.5, 0.3, 0.5), r(0.7, 0.5, 0.3, 0.5)]),
            LayoutPreset(id: "six", name: "Six", frames: (0..<6).map { r(CGFloat($0 % 3) * third, CGFloat($0 / 3) * 0.5, third, 0.5) }),
        ]
    }()

    /// Ways to arrange exactly `count` windows on a screen of `aspect` (width over height), best
    /// first: the even grid, a main window beside the rest, columns, a tall middle, and other
    /// shapes. Layouts with panes too small to use are left out, and so are repeats. With no
    /// windows the fixed presets stand in, for filling panes with apps.
    public static func variations(for count: Int, aspect: CGFloat, limit: Int = 11) -> [LayoutPreset] {
        guard count > 0 else { return all }
        guard count > 1 else { return [all[0]] }
        var result: [LayoutPreset] = []
        func add(_ id: String, _ name: String, _ frames: [CGRect]) {
            guard frames.count == count, frames.allSatisfy({ $0.width >= 0.11 && $0.height >= 0.2 }),
                  !result.contains(where: { same($0.frames, frames) }) else { return }
            result.append(LayoutPreset(id: id, name: name, frames: frames))
        }
        let rest = count - 1
        let even = DesktopGrid.tilingShape(count: count, aspect: aspect)
        add("grid-\(even.columns)x\(even.rows)", gridName(rowsOf(count, rows: even.rows)), rows(rowsOf(count, rows: even.rows)))
        add("main-left", "Main and \(rest) beside", main(rest: rest, mainOnLeft: true))
        add("columns", "\(count) columns", rows([count]))
        add("tall-middle", "Tall middle, sides stacked", tallMiddle(count))
        add("main-right", "\(rest) beside and main", main(rest: rest, mainOnLeft: false))
        // Every other grid shape that fits, by rows and then as stacked columns. A lone window in a
        // row reads as a main window, so more than one of them makes a lopsided layout; stacks of one
        // are already the main-and-beside layouts.
        for rowCount in 1...min(count, DesktopGrid.maxRows) where rowCount != even.rows {
            let split = rowsOf(count, rows: rowCount)
            if split.count == count || split.filter({ $0 == 1 }).count <= 1 { add("grid-rows-\(rowCount)", gridName(split), rows(split)) }
        }
        if count >= 4 { add("two-top", "2 over \(count - 2)", rows([2, count - 2])) }
        add("main-top", "Wide top, \(rest) below", mainTop(rest: rest))
        for columnCount in 2...min(count, DesktopGrid.maxColumns) where count > columnCount {
            let stacks = rowsOf(count, rows: columnCount)
            if stacks.allSatisfy({ $0 >= 2 }) { add("stacks-\(columnCount)", "Stacks of " + stacks.map(String.init).joined(separator: ", "), columns(stacks)) }
        }
        if count == 3 { add("wide-middle", "Wide middle", all.first { $0.id == "wide-middle" }!.frames) }
        return Array(result.prefix(limit))
    }

    /// `count` split into `rows` near-equal rows, the larger ones first.
    public static func rowsOf(_ count: Int, rows: Int) -> [Int] {
        (0..<rows).map { count / rows + ($0 < count % rows ? 1 : 0) }
    }

    private static func gridName(_ rows: [Int]) -> String {
        if rows.count == 1 { return "\(rows[0]) columns" }
        if rows.allSatisfy({ $0 == 1 }) { return "\(rows.count) rows" }
        if Set(rows).count == 1 { return "\(rows[0]) × \(rows.count) grid" }
        return rows.map(String.init).joined(separator: " over ")
    }

    /// Rows of equal height, each split into equal panes.
    static func rows(_ counts: [Int], in area: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [CGRect] {
        let height = area.height / CGFloat(counts.count)
        return counts.enumerated().flatMap { row, count in
            (0..<count).map { column in
                CGRect(x: area.minX + area.width * CGFloat(column) / CGFloat(count), y: area.minY + height * CGFloat(row),
                       width: area.width / CGFloat(count), height: height)
            }
        }
    }

    /// Columns of equal width, each stacked into equal panes.
    static func columns(_ counts: [Int], in area: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [CGRect] {
        rows(counts, in: CGRect(x: area.minY, y: area.minX, width: area.height, height: area.width))
            .map { CGRect(x: $0.minY, y: $0.minX, width: $0.height, height: $0.width) }
    }

    /// One main window taking half the screen; the rest stacked beside it, or in two stacks past four.
    private static func main(rest: Int, mainOnLeft: Bool) -> [CGRect] {
        let mainWidth: CGFloat = rest == 1 ? 0.5 : 0.55
        let mainFrame = CGRect(x: mainOnLeft ? 0 : 1 - mainWidth, y: 0, width: mainWidth, height: 1)
        let side = CGRect(x: mainOnLeft ? mainWidth : 0, y: 0, width: 1 - mainWidth, height: 1)
        let others = rest <= 4 ? columns([rest], in: side) : columns(rowsOf(rest, rows: 2), in: side)
        return [mainFrame] + others
    }

    private static func mainTop(rest: Int) -> [CGRect] {
        [CGRect(x: 0, y: 0, width: 1, height: 0.6)] + rows([rest], in: CGRect(x: 0, y: 0.6, width: 1, height: 0.4))
    }

    /// A tall window in the middle, the rest stacked on both sides, the left taking any extra.
    private static func tallMiddle(_ count: Int) -> [CGRect] {
        // With three windows it's just columns; the sides need two to stack.
        guard count >= 4 else { return [] }
        let left = (count - 1 + 1) / 2, right = count - 1 - left
        return columns([left], in: CGRect(x: 0, y: 0, width: 0.3, height: 1))
            + [CGRect(x: 0.3, y: 0, width: 0.4, height: 1)]
            + columns([right], in: CGRect(x: 0.7, y: 0, width: 0.3, height: 1))
    }

    private static func same(_ a: [CGRect], _ b: [CGRect]) -> Bool {
        guard a.count == b.count else { return false }
        var unmatched = b
        for frame in a {
            guard let index = unmatched.firstIndex(where: { abs($0.minX - frame.minX) < 0.01 && abs($0.minY - frame.minY) < 0.01
                && abs($0.width - frame.width) < 0.01 && abs($0.height - frame.height) < 0.01 }) else { return false }
            unmatched.remove(at: index)
        }
        return true
    }

    /// The frames with `gap` between neighbors and none at the screen's edges.
    public func frames(gap: CGSize) -> [CGRect] {
        frames.map { frame in
            let left = frame.minX < 0.001 ? 0 : gap.width / 2, right = frame.maxX > 0.999 ? 0 : gap.width / 2
            let top = frame.minY < 0.001 ? 0 : gap.height / 2, bottom = frame.maxY > 0.999 ? 0 : gap.height / 2
            return CGRect(x: frame.minX + left, y: frame.minY + top,
                          width: frame.width - left - right, height: frame.height - top - bottom)
        }
    }
}

extension DesktopGrid {
    /// The grid's panes moved into `preset`, in reading order. Spare spaces stay empty; panes past
    /// the preset's count are left out, so their windows are minimized on Apply like any other
    /// pane a layout change drops.
    public func arranged(in preset: LayoutPreset, gap: CGSize = CGSize(width: 0.008, height: 0.008)) -> DesktopGrid {
        let panes = readingOrder.map { slots[$0] }.filter { $0.app != nil }
        let frames = preset.frames(gap: gap)
        let order = DesktopGrid(panes: frames.map { _ in GridSlot() }, frames: frames).readingOrder
        var next = DesktopGrid(panes: frames.map { _ in GridSlot() }, frames: order.map { frames[$0] })
        for (index, pane) in panes.prefix(frames.count).enumerated() { next.slots[index] = pane }
        next.windowsToClose = windowsToClose
        return next
    }

    /// True when the panes already sit in `preset`'s arrangement, whatever their gaps.
    public func matches(_ preset: LayoutPreset, tolerance: CGFloat = 0.02) -> Bool {
        let mine = normalizedFrames
        guard mine.count == preset.frames.count else { return false }
        var unmatched = preset.frames
        for frame in mine {
            guard let index = unmatched.firstIndex(where: {
                abs($0.midX - frame.midX) < tolerance && abs($0.midY - frame.midY) < tolerance
                    && abs($0.width - frame.width) < tolerance * 2 && abs($0.height - frame.height) < tolerance * 2
            }) else { return false }
            unmatched.remove(at: index)
        }
        return true
    }
}
