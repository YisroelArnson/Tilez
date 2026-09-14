import Foundation
import CoreGraphics

public enum Placement: String, CaseIterable, Codable, Identifiable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case firstThird, middleThird, lastThird, maximize, center
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .left: return "Left • cycle ½ → ⅓ → ⅔"
        case .right: return "Right • cycle ½ → ⅓ → ⅔"
        case .top: return "Top • cycle ½ → ⅓ → ⅔"
        case .bottom: return "Bottom • cycle ½ → ⅓ → ⅔"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        case .firstThird: return "First third"
        case .middleThird: return "Middle third"
        case .lastThird: return "Last third"
        case .maximize: return "Maximize"
        case .center: return "Center"
        }
    }
}

public enum Geometry {
    // All geometry uses the Accessibility coordinate system: origin at the top left.
    public static func grid(count: Int, in bounds: CGRect, columns: Int = 0, rows: Int = 0, gap: Double = 8) -> [CGRect] {
        guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        var c = columns > 0 ? min(columns, count) : 0
        var r = rows > 0 ? rows : 0
        if c == 0 && r == 0 {
            var best = Double.infinity
            for candidate in 1...count {
                let rr = Int(ceil(Double(count) / Double(candidate)))
                let aspect = (bounds.width / Double(candidate)) / (bounds.height / Double(rr))
                let cost = abs(log(aspect / 1.3)) + Double(candidate * rr - count) / Double(count) * 0.65
                if cost < best { best = cost; c = candidate; r = rr }
            }
        } else if c == 0 {
            r = min(r, count)
            c = Int(ceil(Double(count) / Double(r)))
        } else {
            r = max(r, Int(ceil(Double(count) / Double(c))))
        }
        let g = max(0, min(gap, bounds.width / Double(c + 1) / 2, bounds.height / Double(r + 1) / 2))
        let w = (bounds.width - g * Double(c + 1)) / Double(c)
        let h = (bounds.height - g * Double(r + 1)) / Double(r)
        return (0..<count).map { index in
            CGRect(x: bounds.minX + g + Double(index % c) * (w + g),
                   y: bounds.minY + g + Double(index / c) * (h + g), width: w, height: h)
        }
    }

    public static func placement(_ placement: Placement, in b: CGRect, current: CGRect, cycle: Int = 0, gap: Double = 8) -> CGRect {
        let fraction = [0.5, 1.0 / 3.0, 2.0 / 3.0][abs(cycle) % 3]
        var r = b
        switch placement {
        case .left: r.size.width *= fraction
        case .right: r.size.width *= fraction; r.origin.x = b.maxX - r.width
        case .top: r.size.height *= fraction
        case .bottom: r.size.height *= fraction; r.origin.y = b.maxY - r.height
        case .topLeft: r.size = CGSize(width: b.width / 2, height: b.height / 2)
        case .topRight: r = CGRect(x: b.midX, y: b.minY, width: b.width / 2, height: b.height / 2)
        case .bottomLeft: r = CGRect(x: b.minX, y: b.midY, width: b.width / 2, height: b.height / 2)
        case .bottomRight: r = CGRect(x: b.midX, y: b.midY, width: b.width / 2, height: b.height / 2)
        case .firstThird: r.size.width /= 3
        case .middleThird: r.size.width /= 3; r.origin.x += b.width / 3
        case .lastThird: r.size.width /= 3; r.origin.x += b.width * 2 / 3
        case .maximize: return b.insetBy(dx: gap, dy: gap)
        case .center:
            let size = CGSize(width: min(current.width, b.width - 2 * gap), height: min(current.height, b.height - 2 * gap))
            return CGRect(x: b.midX - size.width / 2, y: b.midY - size.height / 2, width: size.width, height: size.height)
        }
        // Adjacent regions each contribute half of the interior gap.
        let left = abs(r.minX - b.minX) < 1 ? gap : gap / 2
        let top = abs(r.minY - b.minY) < 1 ? gap : gap / 2
        let right = abs(r.maxX - b.maxX) < 1 ? gap : gap / 2
        let bottom = abs(r.maxY - b.maxY) < 1 ? gap : gap / 2
        return CGRect(x: r.minX + left, y: r.minY + top, width: max(1, r.width - left - right), height: max(1, r.height - top - bottom))
    }

    public static func normalized(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: (rect.minX - bounds.minX) / bounds.width, y: (rect.minY - bounds.minY) / bounds.height,
               width: rect.width / bounds.width, height: rect.height / bounds.height)
    }
    public static func restored(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let w = max(1, min(rect.width * bounds.width, bounds.width))
        let h = max(1, min(rect.height * bounds.height, bounds.height))
        return CGRect(x: max(bounds.minX, min(bounds.minX + rect.minX * bounds.width, bounds.maxX - w)),
                      y: max(bounds.minY, min(bounds.minY + rect.minY * bounds.height, bounds.maxY - h)), width: w, height: h)
    }
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: Double = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
