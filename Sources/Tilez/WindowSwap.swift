import AppKit
import ApplicationServices

/// Drag a window by its title bar and pause over another window to swap them: the dragged
/// window takes the other's frame and the other takes the dragged window's original frame.
/// A drag that never pauses over a window stays an ordinary move.
@MainActor final class WindowSwap {
    private struct Drag { let element: AXUIElement; let number: UInt32?; let origin: CGRect }
    private struct Hover { let number: UInt32; let pid: pid_t; let frame: CGRect }
    private struct Target { let element: AXUIElement; let frame: CGRect }
    private var drag: Drag?
    private var hover: Hover?
    private var target: Target?
    private var lookup: Task<Void, Never>?
    private var dwell: Task<Void, Never>?
    private var lastCheck = Date.distantPast
    private var monitor: Any?
    private let destination = SwapPreview(dashed: false)
    private let returning = SwapPreview(dashed: true)
    /// Enlarged windows keep their own restore frame, so they never take part in a swap.
    var isExcluded: (AXUIElement) -> Bool = { _ in false }

    init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown: begin(at: Display.pointer)
        case .leftMouseDragged: dragged(to: Display.pointer)
        case .leftMouseUp: finish()
        default: break
        }
    }

    private func begin(at point: CGPoint) {
        cancel()
        guard Accessibility.trusted else { return }
        lookup = Task { [weak self] in
            guard let found = (try? await Accessibility.perform { Self.titleBarWindow(at: point) }) ?? nil,
                  let self, !self.isExcluded(found.element) else { return }
            self.drag = Drag(element: found.element, number: found.number, origin: found.frame)
        }
    }

    private func dragged(to point: CGPoint) {
        guard let drag, Date().timeIntervalSince(lastCheck) > 0.04 else { return }
        lastCheck = Date()
        let under = Self.window(below: point, excluding: drag.number)
        guard under?.number != hover?.number else { return }
        // Moving onto a different window (or off all of them) starts the pause over.
        hover = under
        target = nil
        destination.hide(); returning.hide()
        dwell?.cancel()
        guard let under else { return }
        dwell = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.arm(under, for: drag)
        }
    }

    /// The pause completed: confirm the dragged window really moved and find the target's AX window.
    private func arm(_ under: Hover, for drag: Drag) async {
        let found = try? await Accessibility.perform { () -> Target? in
            guard let now = Accessibility.rect(drag.element),
                  abs(now.minX - drag.origin.minX) + abs(now.minY - drag.origin.minY) > 20,
                  let element = Self.axWindow(pid: under.pid, number: under.number),
                  Accessibility.value(element, "AXFullScreen") as? Bool != true,
                  let frame = Accessibility.rect(element) else { return nil }
            return Target(element: element, frame: frame)
        }
        guard let found = found ?? nil, hover?.number == under.number, self.drag != nil, !isExcluded(found.element) else { return }
        target = found
        destination.show(found.frame)
        returning.show(drag.origin)
    }

    private func finish() {
        defer { cancel() }
        guard let drag, let target else { return }
        let origin = drag.origin
        Task {
            // The app may still be settling its own drag; apply once more after it lets go.
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 150_000_000) }
                _ = try? await Accessibility.perform {
                    Accessibility.setFrame(drag.element, to: target.frame)
                    Accessibility.setFrame(target.element, to: origin)
                }
            }
        }
    }

    private func cancel() {
        lookup?.cancel(); dwell?.cancel()
        drag = nil; hover = nil; target = nil
        destination.hide(); returning.hide()
    }

    /// A standard window whose title area (its top 60 points, outside any control) is under `point`.
    nonisolated private static func titleBarWindow(at point: CGPoint) -> (element: AXUIElement, number: UInt32?, frame: CGRect)? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid != getpid() else { return nil }
        let role = Accessibility.value(hit, kAXRoleAttribute) as? String ?? ""
        guard ![kAXButtonRole, kAXTextFieldRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXCheckBoxRole, kAXRadioButtonRole].contains(role) else { return nil }
        let window = Accessibility.value(hit, kAXWindowAttribute).flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        } ?? hit
        guard Accessibility.value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              Accessibility.value(window, "AXFullScreen") as? Bool != true,
              let frame = Accessibility.rect(window), frame.contains(point), point.y < frame.minY + 60 else { return nil }
        return (window, Desktops.windowNumber(window), frame)
    }

    /// WindowServer's front-to-back list finds the window under the pointer without AX IPC.
    nonisolated private static func window(below point: CGPoint, excluding number: UInt32?) -> Hover? {
        let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for record in records {
            guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let windowNumber = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value, windowNumber != number,
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != getpid(),
                  let raw = record[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw), frame.width > 100, frame.height > 80,
                  frame.contains(point) else { continue }
            return Hover(number: windowNumber, pid: pid, frame: frame)
        }
        return nil
    }

    nonisolated private static func axWindow(pid: pid_t, number: UInt32) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let windows = Accessibility.value(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return windows.first { Desktops.windowNumber($0) == number }
    }
}

/// A frosted outline over a window frame: solid where the dragged window will land,
/// dashed where the other window will go.
@MainActor private final class SwapPreview {
    private let dashed: Bool
    private var panel: NSPanel?
    init(dashed: Bool) { self.dashed = dashed }

    func show(_ frame: CGRect) {
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = SwapPreviewView(dashed: dashed)
            self.panel = panel
        }
        panel?.setFrame(Display.cocoa(frame), display: true)
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

private final class SwapPreviewView: NSView {
    private let dashed: Bool
    init(dashed: Bool) { self.dashed = dashed; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("Not supported") }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 14, yRadius: 14)
        NSColor.white.withAlphaComponent(dashed ? 0.06 : 0.14).setFill(); path.fill()
        NSColor.white.withAlphaComponent(dashed ? 0.55 : 0.8).setStroke()
        path.lineWidth = 2.5
        if dashed { path.setLineDash([10, 7], count: 2, phase: 0) }
        path.stroke()
    }
}
