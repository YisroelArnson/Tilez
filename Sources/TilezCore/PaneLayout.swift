import Foundation
import CoreGraphics

public enum PaneEdge: String, CaseIterable { case left, right, top, bottom }

public struct PaneDivider: Identifiable {
    public let before: Int
    public let after: Int
    public let vertical: Bool
    public let position: CGFloat
    public let lower: CGFloat
    public let upper: CGFloat
    public var id: String { "\(before)-\(after)-\(vertical)" }
}

extension DesktopGrid {
    public static var emptyDesktop: DesktopGrid {
        DesktopGrid(panes: [GridSlot()], frames: [CGRect(x: 0, y: 0, width: 1, height: 1)])
    }

    public init(panes: [GridSlot], frames: [CGRect]) {
        self.init(columns: 1, rows: 1)
        slots = panes
        paneFrames = frames
    }

    /// Import window geometry without rounding unequal panes into a guessed grid.
    public static func desktop(panes: [(GridSlot, CGRect)], in bounds: CGRect) -> DesktopGrid {
        let visible = panes.compactMap { slot, frame -> (GridSlot, CGRect)? in
            let clipped = bounds.intersection(frame)
            guard !clipped.isNull, clipped.width > 1, clipped.height > 1, bounds.width > 0, bounds.height > 0 else { return nil }
            return (slot, CGRect(x: (clipped.minX - bounds.minX) / bounds.width,
                                 y: (clipped.minY - bounds.minY) / bounds.height,
                                 width: clipped.width / bounds.width, height: clipped.height / bounds.height))
        }
        return visible.isEmpty ? .emptyDesktop : DesktopGrid(panes: visible.map(\.0), frames: visible.map(\.1))
    }

    /// WindowServer lists fully occluded windows too. Keep panes with a visible
    /// portion so a window buried under a tiled desktop doesn't become a phantom cell.
    public static func visibleDesktop(panes: [(GridSlot, CGRect)], in bounds: CGRect) -> DesktopGrid {
        var covering: [CGRect] = []
        let visible = panes.filter { _, frame in
            let clipped = bounds.intersection(frame)
            guard !clipped.isNull else { return false }
            var remaining = [clipped]
            for cover in covering {
                remaining = remaining.flatMap { piece -> [CGRect] in
                    let intersection = piece.intersection(cover)
                    guard !intersection.isNull && intersection.width > 0 && intersection.height > 0 else { return [piece] }
                    return [
                        CGRect(x: piece.minX, y: piece.minY, width: intersection.minX - piece.minX, height: piece.height),
                        CGRect(x: intersection.maxX, y: piece.minY, width: piece.maxX - intersection.maxX, height: piece.height),
                        CGRect(x: intersection.minX, y: piece.minY, width: intersection.width, height: intersection.minY - piece.minY),
                        CGRect(x: intersection.minX, y: intersection.maxY, width: intersection.width, height: piece.maxY - intersection.maxY)
                    ].filter { $0.width > 0.5 && $0.height > 0.5 }
                }
                if remaining.isEmpty { break }
            }
            covering.append(clipped)
            return remaining.reduce(CGFloat(0)) { $0 + $1.width * $1.height } > 4
        }
        return desktop(panes: visible, in: bounds)
    }

    public func frames(in bounds: CGRect, gap: CGFloat = 10) -> [CGRect] {
        guard let paneFrames else { return Geometry.grid(count: slots.count, in: bounds, columns: columns, rows: rows, gap: gap) }
        return paneFrames.map { CGRect(x: bounds.minX + $0.minX * bounds.width, y: bounds.minY + $0.minY * bounds.height,
                                      width: $0.width * bounds.width, height: $0.height * bounds.height) }
    }

    public var normalizedFrames: [CGRect] {
        paneFrames ?? Geometry.grid(count: slots.count, in: CGRect(x: 0, y: 0, width: 1, height: 1), columns: columns, rows: rows, gap: 0.008)
    }

    /// Splitting changes geometry only; choosing the app happens separately.
    @discardableResult public mutating func split(_ index: Int, toward edge: PaneEdge, gap: CGSize = CGSize(width: 0.008, height: 0.008)) -> Int? {
        guard slots.indices.contains(index), slots.count < 64 else { return nil }
        var frames = normalizedFrames
        let old = frames[index]
        let vertical = edge == .left || edge == .right
        let spacing = vertical ? gap.width : gap.height
        let length = ((vertical ? old.width : old.height) - spacing) / 2
        guard length >= 0.04 else { return nil }
        var first = old, second = old
        if vertical {
            first.size.width = length; second.size.width = length
            second.origin.x = first.maxX + spacing
        } else {
            first.size.height = length; second.size.height = length
            second.origin.y = first.maxY + spacing
        }
        let newFirst = edge == .left || edge == .top
        frames[index] = newFirst ? second : first
        frames.append(newFirst ? first : second)
        slots.append(GridSlot())
        paneFrames = frames
        return slots.count - 1
    }

    /// Remove only the assignment. Expand a rectangular neighbor/group into the hole
    /// when possible; otherwise preserve the other panes' exact geometry.
    public mutating func removePane(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        if slots.count == 1 { self = .emptyDesktop; return }
        var frames = normalizedFrames
        let removed = frames[index]
        let tolerance: CGFloat = 0.025
        for edge in PaneEdge.allCases {
            let vertical = edge == .left || edge == .right
            let candidates = frames.indices.filter { other in
                guard other != index else { return false }
                let f = frames[other]
                let gap: CGFloat
                switch edge {
                case .left: gap = removed.minX - f.maxX
                case .right: gap = f.minX - removed.maxX
                case .top: gap = removed.minY - f.maxY
                case .bottom: gap = f.minY - removed.maxY
                }
                let low = vertical ? f.minY : f.minX, high = vertical ? f.maxY : f.maxX
                let start = vertical ? removed.minY : removed.minX, end = vertical ? removed.maxY : removed.maxX
                return gap >= -0.001 && gap <= tolerance && low >= start - 0.001 && high <= end + 0.001
            }.sorted { (vertical ? frames[$0].minY : frames[$0].minX) < (vertical ? frames[$1].minY : frames[$1].minX) }
            guard let first = candidates.first, let last = candidates.last else { continue }
            let start = vertical ? removed.minY : removed.minX, end = vertical ? removed.maxY : removed.maxX
            guard abs((vertical ? frames[first].minY : frames[first].minX) - start) < 0.002,
                  abs((vertical ? frames[last].maxY : frames[last].maxX) - end) < 0.002 else { continue }
            let contiguous = zip(candidates, candidates.dropFirst()).allSatisfy {
                let gap = vertical ? frames[$1].minY - frames[$0].maxY : frames[$1].minX - frames[$0].maxX
                return gap >= -0.001 && gap <= tolerance
            }
            guard contiguous else { continue }
            for other in candidates {
                switch edge {
                case .left: frames[other].size.width = removed.maxX - frames[other].minX
                case .right: let end = frames[other].maxX; frames[other].origin.x = removed.minX; frames[other].size.width = end - removed.minX
                case .top: frames[other].size.height = removed.maxY - frames[other].minY
                case .bottom: let end = frames[other].maxY; frames[other].origin.y = removed.minY; frames[other].size.height = end - removed.minY
                }
            }
            break
        }
        frames.remove(at: index); slots.remove(at: index); paneFrames = frames
    }

    public var dividers: [PaneDivider] {
        let frames = normalizedFrames
        var result: [PaneDivider] = []
        for before in frames.indices {
            for after in frames.indices where before != after {
                let a = frames[before], b = frames[after]
                for vertical in [true, false] {
                    let gap = vertical ? b.minX - a.maxX : b.minY - a.maxY
                    let lower = vertical ? max(a.minY, b.minY) : max(a.minX, b.minX)
                    let upper = vertical ? min(a.maxY, b.maxY) : min(a.maxX, b.maxX)
                    if gap >= -0.001 && gap <= 0.025 && upper - lower > 0.02 {
                        result.append(PaneDivider(before: before, after: after, vertical: vertical,
                            position: vertical ? (a.maxX + b.minX) / 2 : (a.maxY + b.minY) / 2, lower: lower, upper: upper))
                    }
                }
            }
        }
        return result
    }

    /// Include T junctions: every pane sharing the connected boundary moves together.
    private func sides(of divider: PaneDivider) -> (before: Set<Int>, after: Set<Int>) {
        var before: Set<Int> = [divider.before], after: Set<Int> = [divider.after]
        var changed = true
        let shared = dividers.filter { $0.vertical == divider.vertical && abs($0.position - divider.position) < 0.002 }
        while changed {
            let count = before.count + after.count
            for d in shared where before.contains(d.before) || after.contains(d.after) {
                before.insert(d.before); after.insert(d.after)
            }
            changed = before.count + after.count != count
        }
        return (before, after)
    }

    public mutating func resizeDivider(_ divider: PaneDivider, to position: CGFloat) {
        var frames = normalizedFrames
        guard frames.indices.contains(divider.before), frames.indices.contains(divider.after), position.isFinite else { return }
        let vertical = divider.vertical
        let (before, after) = sides(of: divider)
        let minimum: CGFloat = 0.04
        let lower = before.map { minimum - (vertical ? frames[$0].width : frames[$0].height) }.max() ?? 0
        let upper = after.map { (vertical ? frames[$0].width : frames[$0].height) - minimum }.min() ?? 0
        guard lower <= upper else { return }
        let delta = max(lower, min(upper, position - divider.position))
        for i in before {
            if vertical { frames[i].size.width += delta } else { frames[i].size.height += delta }
        }
        for i in after {
            if vertical { frames[i].origin.x += delta; frames[i].size.width -= delta }
            else { frames[i].origin.y += delta; frames[i].size.height -= delta }
        }
        paneFrames = frames
    }

    /// Double-click reset: center the divider in the span its adjacent panes share,
    /// which undoes a drag away from an even split.
    public mutating func resetDivider(_ divider: PaneDivider) {
        let frames = normalizedFrames
        guard frames.indices.contains(divider.before), frames.indices.contains(divider.after) else { return }
        let (before, after) = sides(of: divider)
        let start = before.map { divider.vertical ? frames[$0].minX : frames[$0].minY }.max() ?? 0
        let end = after.map { divider.vertical ? frames[$0].maxX : frames[$0].maxY }.min() ?? 1
        resizeDivider(divider, to: (start + end) / 2)
    }

    /// Panes that exactly fill the space beside `index` on `edge`, so absorbing them
    /// leaves one rectangle. Empty when the panes don't line up.
    public func mergeCandidates(_ index: Int, toward edge: PaneEdge) -> [Int] {
        let frames = normalizedFrames
        guard frames.indices.contains(index) else { return [] }
        let pane = frames[index]
        let across = edge == .left || edge == .right
        let tolerance: CGFloat = 0.004
        func low(_ f: CGRect) -> CGFloat { across ? f.minY : f.minX }
        func high(_ f: CGRect) -> CGFloat { across ? f.maxY : f.maxX }
        func far(_ f: CGRect) -> CGFloat {
            switch edge {
            case .left: return f.minX
            case .right: return f.maxX
            case .top: return f.minY
            case .bottom: return f.maxY
            }
        }
        let neighbors = frames.indices.filter { other in
            guard other != index else { return false }
            let f = frames[other]
            let gap: CGFloat
            switch edge {
            case .left: gap = pane.minX - f.maxX
            case .right: gap = f.minX - pane.maxX
            case .top: gap = pane.minY - f.maxY
            case .bottom: gap = f.minY - pane.maxY
            }
            return gap >= -0.001 && gap <= 0.025 && min(high(f), high(pane)) - max(low(f), low(pane)) > tolerance
        }.sorted { low(frames[$0]) < low(frames[$1]) }
        guard let first = neighbors.first, let last = neighbors.last,
              abs(low(frames[first]) - low(pane)) < tolerance, abs(high(frames[last]) - high(pane)) < tolerance,
              neighbors.allSatisfy({ abs(far(frames[$0]) - far(frames[first])) < tolerance }),
              zip(neighbors, neighbors.dropFirst()).allSatisfy({
                  let gap = low(frames[$1]) - high(frames[$0])
                  return gap >= -0.001 && gap <= 0.025
              }) else { return [] }
        // Overlapping windows inside the merged area would be silently covered.
        let merged = neighbors.reduce(pane) { $0.union(frames[$1]) }.insetBy(dx: tolerance, dy: tolerance)
        let covered = frames.indices.contains { other in
            other != index && !neighbors.contains(other) && frames[other].intersects(merged)
        }
        return covered ? [] : neighbors
    }

    /// Grow `index` over the panes beside it on `edge`. The pane keeps its own app,
    /// or takes the first absorbed app when it was empty. Returns its new index.
    @discardableResult public mutating func merge(_ index: Int, toward edge: PaneEdge) -> Int? {
        let absorbed = mergeCandidates(index, toward: edge)
        guard !absorbed.isEmpty else { return nil }
        var frames = normalizedFrames
        frames[index] = absorbed.reduce(frames[index]) { $0.union(frames[$1]) }
        if slots[index].app == nil, let filled = absorbed.first(where: { slots[$0].app != nil }) {
            slots[index] = slots[filled]
        }
        for other in absorbed.sorted(by: >) { frames.remove(at: other); slots.remove(at: other) }
        paneFrames = frames
        return index - absorbed.filter { $0 < index }.count
    }

    /// Spatial navigation also works for asymmetric arrangements and overlapping windows.
    public func neighbor(of index: Int, dx: Int, dy: Int) -> Int? {
        let frames = normalizedFrames
        guard frames.indices.contains(index) else { return nil }
        let origin = CGPoint(x: frames[index].midX, y: frames[index].midY)
        return frames.indices.filter { other in
            guard other != index else { return false }
            let delta = CGPoint(x: frames[other].midX - origin.x, y: frames[other].midY - origin.y)
            return dx != 0 ? delta.x * CGFloat(dx) > 0.001 : delta.y * CGFloat(dy) > 0.001
        }.min { a, b in
            func score(_ i: Int) -> CGFloat {
                let x = abs(frames[i].midX - origin.x), y = abs(frames[i].midY - origin.y)
                return dx != 0 ? x + y * 3 : y + x * 3
            }
            return score(a) < score(b)
        }
    }

    /// New pane requests cannot consume a pre-existing window that wasn't explicitly bound.
    public func candidateIDs(bundleID: String, session: String, available: [String], initial: Set<String>) -> [String] {
        let choices = slots.filter { $0.app?.bundleID == bundleID }
        let bound = choices.compactMap(\.binding).filter { $0.processSession == session }.map(\.windowID)
        let reusable = choices.filter { $0.binding == nil && $0.opensNewWindow != true }.count
        let existing = available.filter { initial.contains($0) && !bound.contains($0) }.prefix(reusable)
        let created = available.filter { !initial.contains($0) && !bound.contains($0) }
        var seen = Set<String>()
        return (bound.filter { available.contains($0) } + existing + created).filter { seen.insert($0).inserted }
    }
}
