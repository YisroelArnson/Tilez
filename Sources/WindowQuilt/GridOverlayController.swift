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
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?
    private var previousApp: NSRunningApplication?
    var isShown: Bool { panel?.isVisible == true }

    init(manager: WindowManager) {
        model = GridEditorModel(manager: manager)
        model.onDismiss = { [weak self] in self?.close() }
        model.onFinished = { [weak self] in self?.close(restoreFocus: false) }
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
        let target = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let display = Display.all.first(where: { $0.screen == target }) ?? Display.all.first else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        model.begin(on: display)
        if panel == nil {
            let panel = GridPanel(contentRect: display.screen.visibleFrame,
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "Window Quilt — Desktop Grid"
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
        installKeys()
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
        model.persist()
        model.choosingApp = false; model.saving = false; model.showingSaved = false
        panel?.orderOut(nil)
        permissionTimer?.invalidate(); permissionTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if restoreFocus, let previousApp, previousApp.processIdentifier != getpid() {
            previousApp.activate(options: [])
        }
    }
    private func installKeys() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShown else { return event }
            // Preserve normal editing inside search and save-name fields.
            let typing = event.window?.firstResponder is NSTextView
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 { self.model.dismissLayer(); return nil }
            if self.model.busy { return event }
            if modifiers == .command {
                if event.keyCode == 40 { self.model.addApp(); return nil }
                if !typing && event.keyCode == 6 { self.model.undo(); return nil }
                if !typing && event.keyCode == 45 { self.model.newGrid(); return nil }
            }
            if !typing && modifiers.isEmpty {
                if event.keyCode == 36 && !self.model.choosingApp && !self.model.saving && !self.model.showingSaved {
                    self.model.openGrid(); return nil
                }
                if let text = event.characters, let number = Int(text), (1...9).contains(number),
                   self.model.grid.slots.indices.contains(number - 1) { self.model.choose(number - 1); return nil }
                if event.keyCode == 51, let index = self.model.selectedCell { self.model.clear(index); return nil }
                if [123, 124, 125, 126].contains(event.keyCode) && !self.model.choosingApp {
                    let current = self.model.selectedCell ?? 0
                    let delta = event.keyCode == 123 ? -1 : event.keyCode == 124 ? 1 : event.keyCode == 125 ? self.model.grid.columns : -self.model.grid.columns
                    self.model.selectedCell = max(0, min(self.model.grid.slots.count - 1, current + delta))
                    return nil
                }
                if event.keyCode == 49, let index = self.model.selectedCell { self.model.choose(index); return nil }
            }
            return event
        }
    }
}

/// One global shortcut; registered without Accessibility or keyboard-monitoring permission.
final class GridHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    private(set) var registered = false
    init(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == 0x51475244 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<GridHotKey>.fromOpaque(context).takeUnretainedValue().action?()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return }
        registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x51475244, id: 1), GetApplicationEventTarget(), 0, &reference) == noErr
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
