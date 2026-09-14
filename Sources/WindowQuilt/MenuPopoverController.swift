import AppKit
import SwiftUI
import QuiltCore

/// AppKit owns the popover size; the SwiftUI view fills that size without resizing
/// the window after AppKit has positioned it against the status item.
final class MenuPopoverController<Content: View>: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let hosting: NSHostingController<Content>
    private weak var anchor: NSView?
    var isShown: Bool { popover.isShown }
    var window: NSWindow? { hosting.view.window }

    init(rootView: Content) {
        hosting = NSHostingController(rootView: rootView)
        super.init()
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        // A menu picker should dismiss on outside interaction or app activation.
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    func show(relativeTo anchor: NSView, contentSize: CGSize) {
        self.anchor = anchor
        resize(to: contentSize)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        positionBelowAnchor()
        window?.makeKey()
    }

    func resize(to contentSize: CGSize) {
        hosting.view.setFrameSize(contentSize)
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentSize = contentSize
        if isShown { positionBelowAnchor() }
    }

    func close() { popover.performClose(nil) }

    func popoverDidShow(_ notification: Notification) { positionBelowAnchor() }

    private func positionBelowAnchor() {
        guard let anchor, let anchorWindow = anchor.window, let screen = anchorWindow.screen,
              let window else { return }
        let rect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        window.setFrameOrigin(MenuPanelGeometry.origin(panelSize: window.frame.size, anchor: rect, visibleFrame: screen.visibleFrame))
    }
}
