import AppKit
import SwiftUI
import TilezCore

/// ⌃⌥T tiles a screen's windows evenly and ⌃⌥G moves them into the next layout that fits them,
/// both without opening the grid, the way ⌃⌥R realigns. Undo last window arrangement puts them
/// back. A pill names the layout.
@MainActor final class ScreenLayout: ObservableObject {
    /// What the pill says.
    @Published private(set) var message = ""
    private let manager: WindowManager
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    init(manager: WindowManager) { self.manager = manager }

    func tile(on display: Display) async {
        guard let windows = await WindowRealign.arrangeable(on: display, manager: manager), !windows.isEmpty else { return }
        let grid = Self.grid(windows, on: display)
        let order = grid.readingOrder
        let tiled = DesktopGrid.tiling(order.map { grid.slots[$0] }, aspect: display.bounds.width / max(1, display.bounds.height),
                                       gap: Self.gap(on: display))
        apply(tiled, windows: windows, on: display, label: "Tile all")
        let left = windows.count - tiled.slots.count
        show(left > 0 ? "Tiled \(tiled.slots.count) windows · \(left) more stay put" : "Tiled \(tiled.slots.count) window\(tiled.slots.count == 1 ? "" : "s")", on: display)
    }

    func nextLayout(on display: Display) async {
        guard let windows = await WindowRealign.arrangeable(on: display, manager: manager), !windows.isEmpty else { return }
        let grid = Self.grid(windows, on: display)
        guard let next = LayoutPreset.next(after: grid, aspect: display.bounds.width / max(1, display.bounds.height)) else { NSSound.beep(); return }
        apply(grid.arranged(in: next.preset, gap: Self.gap(on: display)), windows: windows, on: display, label: next.preset.name)
        show("\(next.preset.name) · \(next.position) of \(next.total)", on: display)
    }

    /// The windows as panes at their frames, each bound to its window so its new pane can be found.
    private static func grid(_ windows: [ManagedWindow], on display: Display) -> DesktopGrid {
        DesktopGrid.desktop(panes: windows.map { window in
            (GridSlot(app: GridApp(bundleID: window.bundleID, name: window.appName),
                      binding: GridWindowBinding(windowID: window.id, processSession: "")), window.frame)
        }, in: display.bounds)
    }

    private static func gap(on display: Display) -> CGSize {
        CGSize(width: 10 / max(1, display.bounds.width), height: 10 / max(1, display.bounds.height))
    }

    private func apply(_ arranged: DesktopGrid, windows: [ManagedWindow], on display: Display, label: String) {
        let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let frames = arranged.frames(in: display.bounds)
        let changes = arranged.slots.indices.compactMap { index -> (ManagedWindow, CGRect)? in
            arranged.slots[index].binding.flatMap { byID[$0.windowID] }.map { ($0, frames[index]) }
        }
        WindowRealign.move(changes, label: label, manager: manager)
    }

    // MARK: The pill

    private func show(_ message: String, on display: Display) {
        self.message = message
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: LayoutPill(layout: self))
            self.panel = panel
        }
        let size = CGSize(width: 420, height: Metrics.pillHeight + Space.xl * 2)
        let screen = display.screen.visibleFrame
        panel?.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.minY + Space.xl, width: size.width, height: size.height), display: true)
        panel?.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.panel?.orderOut(nil) } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}

private struct LayoutPill: View {
    @ObservedObject var layout: ScreenLayout

    var body: some View {
        Text(layout.message)
            .font(.system(size: 13, weight: .medium)).lineLimit(1)
            .padding(.horizontal, Space.lg).frame(height: Metrics.pillHeight)
            .glassSurface(Capsule())
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
