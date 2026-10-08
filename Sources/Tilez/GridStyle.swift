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
    /// The bottom dock's buttons are larger, with a label and a keycap.
    static let dockControl: CGFloat = 36
    static let dockControlRadius: CGFloat = 10
    static let dockRadius: CGFloat = dockControlRadius + barPadding
    static let dockHeight: CGFloat = dockControl + barPadding * 2
    /// Thin rules between groups of controls.
    static let separatorHeight: CGFloat = 20
}

/// Dark smoked glass. Surfaces are translucent black over the blurred desktop, and everything on
/// them is white at a few fixed strengths, so contrast stays the same everywhere.
enum Palette {
    /// Dims the desktop behind the grid.
    static let scrim = Color.black.opacity(0.32)
    /// Darkens the glass material into smoked glass.
    static let tint = Color.black.opacity(0.38)
    /// Insets on a surface: fields, previews, keycaps, resting cards.
    static let raised = Color.white.opacity(0.06)
    static let hover = Color.white.opacity(0.10)
    static let selected = Color.white.opacity(0.16)
    static let pressed = Color.white.opacity(0.22)
    /// A surface's edge and the rules between groups.
    static let hairline = Color.white.opacity(0.10)
    /// Selection rings and the one emphasized action.
    static let accent = Color.white
    /// The one color in Tilez, kept for an update waiting to install. The menu bar dot matches it.
    static let update = Color(nsColor: .systemBlue)
}

struct GridGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        // Smoked glass in any system appearance.
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

extension View {
    /// The smoked-glass surface that the dock, pills, panels, and prompts sit on, in dark mode.
    func glassSurface<S: InsettableShape>(_ shape: S, reduceTransparency: Bool = false, elevated: Bool = true) -> some View {
        background {
            GridGlass(material: .hudWindow)
                .overlay(reduceTransparency ? Color(white: 0.12) : Palette.tint)
                .clipShape(shape)
        }
        .overlay(shape.strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(elevated ? 0.35 : 0), radius: 30, y: 12)
        .environment(\.colorScheme, .dark)
    }
}

/// A hairline between groups of controls in a bar.
struct BarSeparator: View {
    var body: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: Metrics.separatorHeight)
    }
}
