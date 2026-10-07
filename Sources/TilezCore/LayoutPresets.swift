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
