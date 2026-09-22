import AppKit
import SwiftUI

/// Shared surface and interaction values for the native interface.
enum TilezStyle {
    static let inset: CGFloat = 16
    static let innerRadius: CGFloat = 8
    static let outerRadius: CGFloat = innerRadius + inset
    static let pressScale: CGFloat = 0.96
    static let pressAnimation = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.34, green: 0.80, blue: 0.77, alpha: 1)
            : NSColor(srgbRed: 0.0, green: 0.40, blue: 0.43, alpha: 1)
    })
    static let primaryFill = Color(red: 0.0, green: 0.40, blue: 0.43)
}

private struct TilezSurface: ViewModifier {
    var tinted = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(TilezStyle.inset)
            .background {
                RoundedRectangle(cornerRadius: TilezStyle.outerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        if tinted {
                            RoundedRectangle(cornerRadius: TilezStyle.outerRadius, style: .continuous)
                                .fill(TilezStyle.accent.opacity(scheme == .dark ? 0.07 : 0.035))
                        }
                    }
                    // Native equivalent of the neutral ring + two transparent shadow layers.
                    .overlay {
                        RoundedRectangle(cornerRadius: TilezStyle.outerRadius, style: .continuous)
                            .strokeBorder(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 1, x: 0, y: 1)
                    .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.04), radius: 2, x: 0, y: 2)
            }
    }
}

extension View {
    func tilezSurface(tinted: Bool = false) -> some View { modifier(TilezSurface(tinted: tinted)) }
}

enum TilezButtonRole { case primary, secondary, quiet, destructive }

struct TilezButtonStyle: ButtonStyle {
    var role: TilezButtonRole = .secondary
    var isStatic = false
    var iconOnly = false
    func makeBody(configuration: Configuration) -> some View {
        TilezButtonBody(configuration: configuration, role: role, isStatic: isStatic, iconOnly: iconOnly)
    }
}

private struct TilezButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: TilezButtonRole
    let isStatic: Bool
    let iconOnly: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var pointerEvent: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type)
    }
    private var fill: Color {
        if !enabled { return Color.primary.opacity(0.045) }
        switch role {
        case .primary: return TilezStyle.primaryFill
        case .secondary: return Color(nsColor: .controlBackgroundColor)
        case .quiet, .destructive: return Color.primary.opacity(hovered ? 0.06 : 0)
        }
    }
    private var ink: Color {
        if !enabled { return .secondary }
        if role == .primary { return .white }
        if role == .destructive { return .red }
        return .primary
    }
    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(ink)
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(minWidth: 32, minHeight: 32)
            .background(fill, in: RoundedRectangle(cornerRadius: TilezStyle.innerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TilezStyle.innerRadius, style: .continuous)
                    .strokeBorder(focused ? TilezStyle.accent : (role == .secondary ? Color.primary.opacity(0.10) : .clear), lineWidth: focused ? 2 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: TilezStyle.innerRadius, style: .continuous)
                    .fill(Color.primary.opacity(enabled && (configuration.isPressed || hovered) ? (role == .primary ? 0.10 : 0.035) : 0))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: TilezStyle.innerRadius))
            .scaleEffect(enabled && configuration.isPressed && !isStatic && !reduceMotion && pointerEvent ? TilezStyle.pressScale : 1)
            // Scoped to the press state; page loads and appearance changes never animate.
            .animation(enabled && !isStatic && !reduceMotion && pointerEvent ? TilezStyle.pressAnimation : nil, value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

struct TilezSectionLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

struct TilezWindowRow: View {
    let window: ManagedWindow
    @Binding var selected: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Toggle(isOn: $selected) {
            HStack(spacing: 10) {
                Image(systemName: "macwindow")
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? TilezStyle.accent : .secondary)
                    .frame(width: 18)
                Text(window.title.isEmpty ? "Untitled window" : window.title).lineLimit(1)
                Spacer(minLength: 8)
                if !window.stateLabel.isEmpty {
                    Text(window.stateLabel).font(.caption)
                        .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.045), in: Capsule())
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(minHeight: 36)
        .background(selected ? TilezStyle.accent.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? TilezStyle.accent.opacity(0.22) : .clear, lineWidth: 1)
        }
        .opacity(enabled ? 1 : 0.55)
    }
}
