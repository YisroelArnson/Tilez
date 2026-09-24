import AppKit
import SwiftUI
import Carbon

private final class GridPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class GridOverlayController {
    let model: GridEditorModel
    private var panel: GridPanel?
    private var monitor: Any?
    private var clickMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var previousApp: NSRunningApplication?
    var isShown: Bool { panel?.isVisible == true }

    init(manager: WindowManager, defaults: UserDefaults = .standard) {
        model = GridEditorModel(manager: manager, defaults: defaults)
        model.onDismiss = { [weak self] in self?.close() }
        model.onFinished = { [weak self] in self?.close(restoreFocus: false) }
        model.onFocusGrid = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isShown, !self.model.hasActiveLayer else { return }
                self.panel?.makeKeyAndOrderFront(nil)
                self.panel?.makeFirstResponder(nil)
            }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isShown, !self.model.busy else { return }
                    self.model.cancel(); self.close(restoreFocus: false)
                }
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.cancel(); self?.close(restoreFocus: false) }
            })
    }

    func toggle(on screen: NSScreen? = nil) {
        if isShown { model.cancel(); close(); return }
        show(on: screen)
    }
    func show(on screen: NSScreen? = nil) {
        if isShown { return }
        guard !model.busy else { return }
        let target = targetScreen(screen)
        guard let display = Display.all.first(where: { $0.screen == target }) ?? Display.all.first else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        model.begin(on: display)
        if panel == nil {
            let panel = GridPanel(contentRect: display.screen.visibleFrame,
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "Tilez — Desktop Grid"
            panel.identifier = NSUserInterfaceItemIdentifier("desktop-grid")
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false; panel.isMovable = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: DesktopGridView(model: model))
            self.panel = panel
        }
        panel?.setFrame(display.screen.visibleFrame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(nil)
        installKeys()
        installClicks()
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let allowed = Accessibility.trusted
                if self.model.trusted != allowed { self.model.trusted = allowed }
            }
        }
    }
    func close(restoreFocus: Bool = true) {
        model.endEditing()
        model.closeLayers()
        panel?.orderOut(nil)
        permissionTimer?.invalidate(); permissionTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        if restoreFocus, let previousApp, previousApp.processIdentifier != getpid() {
            previousApp.activate(options: [])
        }
    }
    /// The screen the grid opens on: the one given, else the active app's foremost window's.
    func targetScreen(_ screen: NSScreen? = nil) -> NSScreen? {
        screen ?? keyboardScreen() ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// WindowServer's front-to-back list locates the active app's foremost normal
    /// window without waiting for AX IPC from an unresponsive app.
    private func keyboardScreen() -> NSScreen? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), !rect.isEmpty else { continue }
            return Display.containing(rect)?.screen
        }
        return nil
    }

    /// Clicking onto another screen means you've moved on, so the grid closes there. Global
    /// monitors see only clicks in other apps, never the grid's own.
    private func installClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShown, !self.model.busy, let screen = self.panel?.screen else { return }
                let point = NSEvent.mouseLocation
                guard !NSMouseInRect(point, screen.frame, false),
                      NSScreen.screens.contains(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
                self.model.cancel(); self.close(restoreFocus: false)
            }
        }
    }

    private func installKeys() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown else { return event }
            let editor = event.window?.firstResponder as? NSTextView
            // Let the input method finish or cancel composition before routing keys.
            if editor?.hasMarkedText() == true { return event }
            return self.model.handleKey(event, editingText: editor != nil) ? nil : event
        }
    }
}

/// One global ⌃⌥ shortcut; registered without Accessibility or keyboard-monitoring permission.
/// Each instance needs its own `id` so its handler ignores the other shortcuts.
final class GridHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    var action: (() -> Void)?
    private(set) var registered = false
    init(keyCode: Int = kVK_Space, id: UInt32 = 1, modifiers: Int = controlKey | optionKey, action: @escaping () -> Void) {
        self.action = action; self.id = id
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GridHotKey>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == 0x51475244, id.id == hotkey.id else { return OSStatus(eventNotHandledErr) }
            hotkey.action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return }
        registered = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers),
            EventHotKeyID(signature: 0x51475244, id: id), GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
