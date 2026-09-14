import AppKit
import QuiltCore

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayController {
    private var preview: NSPanel?
    private var drawing: NSPanel?
    private var monitors: [Any] = []
    private weak var manager: WindowManager?
    private var dragWindow: ManagedWindow?
    private var edgeTarget: (Placement, Display)?
    private var swipeWindow: ManagedWindow?
    private var swipeX: Double = 0
    private var swipeY: Double = 0
    private var swipeTriggered = false

    init(manager: WindowManager) {
        self.manager = manager
        manager.onDraw = { [weak self] window in self?.draw(window: window) }
        installMonitors()
    }

    func installMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel], handler: {
            [weak self] event in self?.handle(event)
        }) { monitors.append(monitor) }
    }

    private func handle(_ event: NSEvent) {
        guard let manager, manager.trusted, drawing == nil else { return }
        let point = Display.pointer
        switch event.type {
        case .leftMouseDown:
            dragWindow = manager.preferences.edgeSnap ? Accessibility.window(at: point, in: manager.windows) : nil
            if let window = dragWindow, !Accessibility.isTitleBar(at: point, window: window) { dragWindow = nil }
            edgeTarget = nil
        case .leftMouseDragged:
            guard manager.preferences.edgeSnap, let window = dragWindow,
                  let now = Accessibility.rect(window.element),
                  abs(now.minX - window.frame.minX) > 3 || abs(now.minY - window.frame.minY) > 3 else { hidePreview(); return }
            if let target = target(at: point) {
                edgeTarget = target
                showPreview(Geometry.placement(target.0, in: target.1.bounds, current: now, gap: manager.preferences.gap))
            } else { edgeTarget = nil; hidePreview() }
        case .leftMouseUp:
            if let window = dragWindow, let (placement, display) = edgeTarget,
               let now = Accessibility.rect(window.element),
               abs(now.minX - window.frame.minX) > 3 || abs(now.minY - window.frame.minY) > 3 {
                let destination = Geometry.placement(placement, in: display.bounds, current: now, gap: manager.preferences.gap)
                manager.apply([(window, destination)], label: "Edge snap")
            }
            dragWindow = nil; edgeTarget = nil; hidePreview()
        case .scrollWheel:
            handleSwipe(event, at: point, manager: manager)
        default: break
        }
    }

    private func handleSwipe(_ event: NSEvent, at point: CGPoint, manager: WindowManager) {
        guard manager.preferences.titleSwipe, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipeWindow = Accessibility.window(at: point, in: manager.windows)
            if let window = swipeWindow, !Accessibility.isTitleBar(at: point, window: window) { swipeWindow = nil }
            swipeX = 0; swipeY = 0; swipeTriggered = false
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { swipeWindow = nil; return }
        guard let window = swipeWindow, !swipeTriggered else { return }
        // Normalize natural scrolling so the gesture follows the fingers.
        let direction = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        swipeX += event.scrollingDeltaX * direction
        swipeY += event.scrollingDeltaY * direction
        guard max(abs(swipeX), abs(swipeY)) > 65 else { return }
        swipeTriggered = true
        let placement: Placement = abs(swipeX) > abs(swipeY) ? (swipeX > 0 ? .right : .left) : (swipeY > 0 ? .maximize : .center)
        manager.snap(placement, window: window, cycle: false)
    }

    private func target(at point: CGPoint) -> (Placement, Display)? {
        for display in Display.all {
            let bounds = display.bounds
            guard bounds.insetBy(dx: -10, dy: -32).contains(point) else { continue }
            let left = abs(point.x - bounds.minX) < 20
            let right = abs(point.x - bounds.maxX) < 20
            let top = point.y <= bounds.minY + 20
            let bottom = abs(point.y - bounds.maxY) < 20
            if left && top { return (.topLeft, display) }
            if right && top { return (.topRight, display) }
            if left && bottom { return (.bottomLeft, display) }
            if right && bottom { return (.bottomRight, display) }
            if left { return (.left, display) }
            if right { return (.right, display) }
            if top { return (.maximize, display) }
            if bottom { return (.bottom, display) }
        }
        return nil
    }

    private func showPreview(_ rect: CGRect) {
        if preview == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = PreviewView()
            preview = panel
        }
        preview?.setFrame(Display.cocoa(rect), display: true)
        preview?.orderFrontRegardless()
    }
    private func hidePreview() { preview?.orderOut(nil) }

    func draw(window: ManagedWindow) {
        guard drawing == nil else { return }
        hidePreview()
        let point = NSEvent.mouseLocation
        guard let display = Display.all.first(where: { $0.screen.frame.contains(point) }) ?? Display.containing(window.frame) else { return }
        let panel = OverlayPanel(contentRect: Display.cocoa(display.bounds), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = DrawView(frame: CGRect(origin: .zero, size: display.bounds.size))
        view.onFinish = { [weak self] rect in
            guard let self else { return }
            self.drawing?.orderOut(nil)
            self.drawing = nil
            if let rect {
                let target = CGRect(x: display.bounds.minX + rect.minX, y: display.bounds.minY + rect.minY, width: rect.width, height: rect.height)
                self.manager?.apply([(window, target)], label: "Draw to place")
            }
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
        panel.contentView = view
        drawing = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    deinit { monitors.forEach { NSEvent.removeMonitor($0) } }
}

private final class PreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12)
        NSColor.controlAccentColor.withAlphaComponent(0.23).setFill(); path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke(); path.lineWidth = 3; path.stroke()
    }
}

private final class DrawView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var end: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    private func snapped(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let stepX = bounds.width / 24, stepY = bounds.height / 16
        return CGPoint(x: max(0, min(bounds.width, (p.x / stepX).rounded() * stepX)),
                       y: max(0, min(bounds.height, (p.y / stepY).rounded() * stepY)))
    }
    private var selection: CGRect? {
        guard let start, let end else { return nil }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
    override func mouseDown(with event: NSEvent) { start = snapped(event); end = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { end = snapped(event); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        end = snapped(event)
        if let rect = selection, rect.width >= 80, rect.height >= 80 { onFinish?(rect) }
        else { start = nil; end = nil; needsDisplay = true }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.43).setFill()
        bounds.fill()
        let grid = NSBezierPath()
        for x in 0...24 { grid.move(to: CGPoint(x: bounds.width * Double(x) / 24, y: 0)); grid.line(to: CGPoint(x: bounds.width * Double(x) / 24, y: bounds.height)) }
        for y in 0...16 { grid.move(to: CGPoint(x: 0, y: bounds.height * Double(y) / 16)); grid.line(to: CGPoint(x: bounds.width, y: bounds.height * Double(y) / 16)) }
        NSColor.white.withAlphaComponent(0.10).setStroke(); grid.lineWidth = 0.5; grid.stroke()
        if let rect = selection {
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill(); path.fill()
            NSColor.white.withAlphaComponent(0.85).setStroke(); path.lineWidth = 2; path.stroke()
            let text = "\(Int(rect.width)) × \(Int(rect.height))"
            (text as NSString).draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 12),
                                   withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white])
        }
        let instruction = "Draw a rectangle to place your window    •    Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white]
        let size = (instruction as NSString).size(withAttributes: attributes)
        (instruction as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: 28), withAttributes: attributes)
    }
}
