import AppKit
import ApplicationServices
import Carbon

/// ⌃⌥Return or ⌃⌥-click enlarges a window over its neighbors without moving anything else;
/// ⌃⌥-drag is passed to WindowSwap instead.
/// Each screen and desktop keeps its own enlarged window. It stays enlarged while focus moves
/// elsewhere; only the shortcut or another ⌃⌥-click puts it back exactly.
@MainActor final class WindowZoom {
    private struct Candidate { let element: AXUIElement; let pid: pid_t; let frame: CGRect }
    private struct Zoomed { let element: AXUIElement; let original: CGRect; let observer: AXObserver? }
    /// Keyed by the screen and desktop the window was enlarged on.
    private var zoomed: [String: Zoomed] = [:]
    // Presses and clicks run in order, one at a time.
    private var work: Task<Void, Never>?
    private(set) var hotkey: GridHotKey!
    private var clickTap: CFMachPort?
    private var tapRetry: Timer?
    private var swallowingClick = false
    private var clickStart = CGPoint.zero
    private var dragging = false
    /// ⌃⌥-drag is handed off here (for swapping); a ⌃⌥-click without movement enlarges.
    var onDragBegan: ((CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    init() {
        hotkey = GridHotKey(keyCode: kVK_Return, id: 2) { [weak self] in self?.toggle() }
        installClickTap()
        // The click tap needs Accessibility; keep trying until it is granted.
        if clickTap == nil {
            tapRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.installClickTap() }
            }
        }
    }

    /// The shortcut acts on the focused window's screen and desktop, or the pointer's.
    func toggle() {
        enqueue { [weak self] in
            guard let self else { return }
            guard Accessibility.trusted, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  pid != getpid() else { NSSound.beep(); return }
            let focused = (try? await Accessibility.perform { Self.focusedWindow(pid: pid) }) ?? nil
            guard let display = focused.flatMap({ Display.containing($0.frame) }) ?? Self.pointerDisplay() else { return }
            let key = Self.key(for: display)
            if zoomed[key] != nil { await putBack(key); return }
            guard let focused else { NSSound.beep(); return }
            // A window already enlarged elsewhere is put back rather than enlarged twice.
            if let other = zoomed.first(where: { CFEqual($0.value.element, focused.element) })?.key {
                await putBack(other); return
            }
            await enlarge(focused, on: display, key: key)
        }
    }

    /// ⌃⌥-click acts on the clicked window: an enlarged one goes back, any other is enlarged.
    private func toggle(at point: CGPoint) {
        enqueue { [weak self] in
            guard let self else { return }
            guard let hit = (try? await Accessibility.perform { Self.window(at: point) }) ?? nil else { NSSound.beep(); return }
            if let key = zoomed.first(where: { CFEqual($0.value.element, hit.element) })?.key {
                await putBack(key); return
            }
            guard let display = Display.containing(hit.frame) else { return }
            let key = Self.key(for: display)
            await putBack(key)
            await enlarge(hit, on: display, key: key)
        }
    }

    func hasEnlarged(on display: Display) -> Bool { zoomed[Self.key(for: display)] != nil }
    func isEnlarged(_ element: AXUIElement) -> Bool { zoomed.values.contains { CFEqual($0.element, element) } }

    /// Puts back this screen's enlarged window before the grid captures its desktop.
    func restore(on display: Display) async {
        let key = Self.key(for: display)
        enqueue { [weak self] in await self?.putBack(key) }
        await work?.value
    }

    /// Quitting cannot wait for the worker, so these writes happen synchronously.
    func restoreBeforeQuit() {
        for (key, window) in zoomed {
            unwatch(window.observer)
            Accessibility.setFrame(window.element, to: window.original)
            zoomed[key] = nil
        }
    }

    private static func key(for display: Display) -> String {
        Desktops.current(displayID: display.id, includeFullScreen: true)?.id ?? display.id
    }

    private static func pointerDisplay() -> Display? {
        let pointer = NSEvent.mouseLocation
        return Display.all.first { NSMouseInRect(pointer, $0.screen.frame, false) }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func enlarge(_ window: Candidate, on display: Display, key: String) async {
        // The same 10-point margin the grid leaves between panes and the screen edge.
        let target = display.bounds.insetBy(dx: 10, dy: 10)
        zoomed[key] = Zoomed(element: window.element, original: window.frame,
                             observer: watch(pid: window.pid, window: window.element))
        _ = try? await Accessibility.perform {
            Accessibility.setFrame(window.element, to: target)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
        // A clicked window's app may be behind the active one.
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    private func putBack(_ key: String) async {
        guard let window = zoomed.removeValue(forKey: key) else { return }
        unwatch(window.observer)
        _ = try? await Accessibility.perform { Accessibility.setFrame(window.element, to: window.original) }
    }

    nonisolated private static func focusedWindow(pid: pid_t) -> Candidate? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let value = Accessibility.value(app, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return candidate(value as! AXUIElement, pid: pid)
    }

    nonisolated private static func window(at point: CGPoint) -> Candidate? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid != getpid() else { return nil }
        let window = Accessibility.value(hit, kAXWindowAttribute).flatMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        } ?? hit
        return candidate(window, pid: pid)
    }

    /// Only standard, resizable windows outside full screen can be enlarged.
    nonisolated private static func candidate(_ window: AXUIElement, pid: pid_t) -> Candidate? {
        var resizable: DarwinBoolean = false
        guard Accessibility.value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              Accessibility.value(window, "AXFullScreen") as? Bool != true,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success, resizable.boolValue,
              let frame = Accessibility.rect(window) else { return nil }
        return Candidate(element: window, pid: pid, frame: frame)
    }

    // ⌃⌥-click is consumed so the app never sees it; macOS treats Control-click as a
    // right-click, which would otherwise open the app's context menu.
    private func installClickTap() {
        guard clickTap == nil, Accessibility.trusted else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let zoom = Unmanaged<WindowZoom>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated { zoom.handleClick(type, event) }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickTap = tap
        tapRetry?.invalidate(); tapRetry = nil
    }

    private func handleClick(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let clickTap { CGEvent.tapEnable(tap: clickTap, enable: true) }
        case .leftMouseDown:
            let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            // Clicks in Tilez's own grid overlay keep their normal behavior.
            guard modifiers == [.maskControl, .maskAlternate],
                  NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() else { break }
            swallowingClick = true
            clickStart = event.location
            dragging = false
            return nil
        case .leftMouseDragged where swallowingClick:
            let point = event.location
            if !dragging, hypot(point.x - clickStart.x, point.y - clickStart.y) > 5 {
                dragging = true
                onDragBegan?(clickStart)
            }
            if dragging { onDragMoved?(point) }
            return nil
        case .leftMouseUp where swallowingClick:
            swallowingClick = false
            // Releasing without moving is a click: enlarge or restore.
            if dragging { onDragEnded?() } else { toggle(at: clickStart) }
            dragging = false
            return nil
        default: break
        }
        return Unmanaged.passUnretained(event)
    }

    /// Closing an enlarged window just forgets it, so the next press there enlarges again.
    private func watch(pid: pid_t, window: AXUIElement) -> AXObserver? {
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, refcon in
            guard let refcon else { return }
            let zoom = Unmanaged<WindowZoom>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { zoom.windowClosed(element) }
        }, &created) == .success, let created else { return nil }
        AXObserverAddNotification(created, window, kAXUIElementDestroyedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        return created
    }

    private func unwatch(_ observer: AXObserver?) {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func windowClosed(_ element: AXUIElement) {
        for (key, window) in zoomed where CFEqual(window.element, element) {
            unwatch(window.observer)
            zoomed[key] = nil
        }
    }
}
