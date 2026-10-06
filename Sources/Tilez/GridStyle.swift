import AppKit
import SwiftUI

/// Spacing on a 4-point scale. Every gap, padding, and inset in Tilez's surfaces comes from here.
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Sizes and corner radii. A container's radius is its content's radius plus the padding
/// between them, so nested corners stay concentric.
enum Metrics {
    /// Every button, chip, and field in a bar or pill is this tall.
    static let control: CGFloat = 32
    static let controlRadius: CGFloat = 8
    /// Thumbnails and previews inside a control, inset by `Space.xs`.
    static let insetRadius: CGFloat = controlRadius - Space.xs
    static let barPadding = Space.sm
    static let barRadius: CGFloat = controlRadius + barPadding
    static let barHeight: CGFloat = control + barPadding * 2
    /// Pills are capsules around a control, inset by `Space.xs`.
    static let pillHeight: CGFloat = control + Space.xs * 2
    static let rowRadius: CGFloat = 6
    static let paneRadius: CGFloat = 12
    /// Thin rules between groups of controls.
    static let separatorHeight: CGFloat = 20
}

struct GridGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

extension View {
    /// The frosted surface that bars, pills, and panels sit on.
    func glassSurface<S: InsettableShape>(_ shape: S, reduceTransparency: Bool = false, elevated: Bool = true) -> some View {
        background {
            GridGlass(material: .popover).overlay(Color.white.opacity(reduceTransparency ? 1 : 0.3)).clipShape(shape)
        }
        .overlay(shape.strokeBorder(.white.opacity(0.7)))
        .shadow(color: .black.opacity(elevated ? 0.16 : 0), radius: 20, y: 8)
    }
}

/// A hairline between groups of controls in a bar.
struct BarSeparator: View {
    var body: some View {
        Rectangle().fill(Color.black.opacity(0.1)).frame(width: 1, height: Metrics.separatorHeight)
    }
}
