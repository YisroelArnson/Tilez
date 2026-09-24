import AppKit
import ApplicationServices

/// ⌃⌥-drag a window to swap it with another. The window follows the pointer; over another
/// window, that window slides into the dragged one's original frame and the dragged one takes
/// its size. Releasing there completes the swap; releasing anywhere else puts the window back
/// exactly where it started. Plain drags are untouched and move windows as usual.
@MainActor final class WindowSwap {
    private struct Drag { let element: AXUIElement; let number: UInt32?; let origin: CGRect; let grab: CGPoint }
    private struct Hover: Equatable { let number: UInt32; let pid: pid_t }
    private struct Target { let number: UInt32; let element: AXUIElement; let frame: CGRect }
    private var drag: Drag?
    private var target: Target?
    private var pointer = CGPoint.zero
    private var lookup: Task<Void, Never>?
    /// The window the drag is heading toward (nil for none), which the pause then confirms.
    private var intent: UInt32?
    private var hoverTask: Task<Void, Never>?
    private var lastHoverCheck = Date.distantPast
    // Moves are coalesced: one AX write in flight, then the latest pointer position.
    private var moving = false
    private var needsMove = false
    private var appliedSize: CGSize?
    /// Enlarged windows keep their own restore frame, so they never take part in a swap.
    var isExcluded: (AXUIElement) -> Bool = { _ in false }

    func begin(at point: CGPoint) {
        reset()
        pointer = point
        lookup = Task { [weak self] in
            guard let found = (try? await Accessibility.perform { Self.window(at: point) }) ?? nil,
                  let self, !self.isExcluded(found.element) else { return }
            let o = found.frame
            self.drag = Drag(element: found.element, number: found.number, origin: o,
                             grab: CGPoint(x: (point.x - o.minX) / max(o.width, 1), y: (point.y - o.minY) / max(o.height, 1)))
            self.appliedSize = o.size
            NSRunningApplication(processIdentifier: found.pid)?.activate()
            _ = try? await Accessibility.perform { AXUIElementPerformAction(found.element, kAXRaiseAction as CFString) }
            self.update()
        }
    }

    func move(to point: CGPoint) {
        pointer = point
        update()
    }

    func end() {
        lookup?.cancel(); hoverTask?.cancel()
        guard let drag else { reset(); return }
        // Over another window the swap completes; anywhere else the window goes home.
        let destination = target?.frame ?? drag.origin
        reset()
        Task {
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 120_000_000) }
                _ = try? await Accessibility.perform { Accessibility.setFrame(drag.element, to: destination) }
            }
        }
    }

    private func reset() {
        lookup?.cancel(); hoverTask?.cancel()
        drag = nil; target = nil; intent = nil
        needsMove = false; appliedSize = nil
    }

    private func update() {
        guard let drag else { return }
        checkHover(for: drag)
        needsMove = true
        pump()
    }

    private func pump() {
        guard !moving, needsMove, let drag else { return }
        needsMove = false
        moving = true
        let size = target?.frame.size ?? drag.origin.size
        let origin = CGPoint(x: pointer.x - drag.grab.x * size.width, y: pointer.y - drag.grab.y * size.height)
        let resize = appliedSize != size
        appliedSize = size
        Task { [weak self] in
            _ = try? await Accessibility.perform {
                if resize { Accessibility.setFrame(drag.element, to: CGRect(origin: origin, size: size)) }
                else { Self.setPosition(drag.element, origin) }
            }
            guard let self else { return }
            self.moving = false
            self.pump()
        }
    }

    /// The displaced window no longer sits under the pointer, so its original frame keeps it
    /// targeted; other windows are found from WindowServer's front-to-back list.
    private func checkHover(for drag: Drag) {
        guard Date().timeIntervalSince(lastHoverCheck) > 0.03 else { return }
        lastHoverCheck = Date()
        let hover: Hover?
        if let target, target.frame.contains(pointer) {
            hover = Hover(number: target.number, pid: 0)
        } else {
            hover = Self.window(below: pointer, excluding: [drag.number, target?.number].compactMap { $0 })
        }
        guard hover?.number != intent else { return }
        intent = hover?.number
        hoverTask?.cancel()
        // A short pause keeps windows from shuffling while the pointer passes over them.
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await self?.retarget(hover, for: drag)
        }
    }

    private func retarget(_ hover: Hover?, for drag: Drag) async {
        guard self.drag != nil, hover?.number != target?.number else { return }
        if let old = target {
            target = nil
            _ = try? await Accessibility.perform { Accessibility.setFrame(old.element, to: old.frame) }
        }
        if let hover {
            let found = try? await Accessibility.perform { () -> Target? in
                guard let element = Self.axWindow(pid: hover.pid, number: hover.number),
                      Accessibility.value(element, "AXFullScreen") as? Bool != true,
                      let frame = Accessibility.rect(element) else { return nil }
                return Target(number: hover.number, element: element, frame: frame)
            }
            if let found = found ?? nil, self.drag != nil, !isExcluded(found.element) {
                target = found
                _ = try? await Accessibility.perform { Accessibility.setFrame(found.element, to: drag.origin) }
            }
        }
        update()
    }

    /// A standard, resizable window under `point`, anywhere in its frame.
    nonisolated private static func window(at point: CGPoint) -> (element: AXUIElement, pid: pid_t, number: UInt32?, frame: CGRect)? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid != getpid() else { return nil }
        let window = Accessibility.value(hit, kAXWindowAttribute).flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        } ?? hit
        var resizable: DarwinBoolean = false
        guard Accessibility.value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              Accessibility.value(window, "AXFullScreen") as? Bool != true,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success, resizable.boolValue,
              let frame = Accessibility.rect(window) else { return nil }
        return (window, pid, Desktops.windowNumber(window), frame)
    }

    /// WindowServer's front-to-back list finds the window under the pointer without AX IPC.
    nonisolated private static func window(below point: CGPoint, excluding numbers: [UInt32]) -> Hover? {
        let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for record in records {
            guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let number = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value, !numbers.contains(number),
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != getpid(),
                  let raw = record[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw), frame.width > 100, frame.height > 80,
                  frame.contains(point) else { continue }
            return Hover(number: number, pid: pid)
        }
        return nil
    }

    nonisolated private static func axWindow(pid: pid_t, number: UInt32) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let windows = Accessibility.value(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return windows.first { Desktops.windowNumber($0) == number }
    }

    nonisolated private static func setPosition(_ element: AXUIElement, _ origin: CGPoint) {
        var point = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }
}
