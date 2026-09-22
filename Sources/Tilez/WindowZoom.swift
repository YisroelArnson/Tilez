import AppKit
import ApplicationServices
import Carbon

/// ⌃⌥Return enlarges the focused window over its neighbors without moving anything else.
/// Each screen and desktop keeps its own enlarged window. It stays enlarged while focus moves
/// elsewhere; only the shortcut, pressed on that same screen and desktop, puts it back exactly.
@MainActor final class WindowZoom {
    private struct Zoomed { let element: AXUIElement; let original: CGRect; let observer: AXObserver? }
    /// Keyed by the screen and desktop the window was enlarged on.
    private var zoomed: [String: Zoomed] = [:]
    // Presses run in order, one at a time.
    private var work: Task<Void, Never>?
    private(set) var hotkey: GridHotKey!

    init() {
        hotkey = GridHotKey(keyCode: kVK_Return, id: 2) { [weak self] in self?.toggle() }
    }

    func toggle() {
        enqueue { [weak self] in
            guard let self else { return }
            guard Accessibility.trusted, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  pid != getpid() else { NSSound.beep(); return }
            let focused = (try? await Accessibility.perform { Self.focusedWindow(pid: pid) }) ?? nil
            // The press applies where focus is, or under the pointer when no window can be enlarged.
            guard let display = focused.flatMap({ Display.containing($0.1) }) ?? Self.pointerDisplay() else { return }
            let key = Self.key(for: display)
            if zoomed[key] != nil { await putBack(key); return }
            guard let (window, frame) = focused else { NSSound.beep(); return }
            // A window already enlarged elsewhere is put back rather than enlarged twice.
            if let other = zoomed.first(where: { CFEqual($0.value.element, window) })?.key {
                await putBack(other); return
            }
            // The same 10-point margin the grid leaves between panes and the screen edge.
            let target = display.bounds.insetBy(dx: 10, dy: 10)
            zoomed[key] = Zoomed(element: window, original: frame, observer: watch(pid: pid, window: window))
            _ = try? await Accessibility.perform {
                Accessibility.setFrame(window, to: target)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        }
    }

    func hasEnlarged(on display: Display) -> Bool { zoomed[Self.key(for: display)] != nil }

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

    private func putBack(_ key: String) async {
        guard let window = zoomed.removeValue(forKey: key) else { return }
        unwatch(window.observer)
        _ = try? await Accessibility.perform { Accessibility.setFrame(window.element, to: window.original) }
    }

    /// Only standard, resizable windows outside full screen can be enlarged.
    nonisolated private static func focusedWindow(pid: pid_t) -> (AXUIElement, CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let value = Accessibility.value(app, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        var resizable: DarwinBoolean = false
        guard Accessibility.value(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
              Accessibility.value(window, "AXFullScreen") as? Bool != true,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success, resizable.boolValue,
              let frame = Accessibility.rect(window) else { return nil }
        return (window, frame)
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
