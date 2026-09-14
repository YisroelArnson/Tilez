import AppKit
import Carbon
import SwiftUI

final class HotKeyCenter {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let manager: WindowManager
    var suspended = false { didSet { register() } }

    init(manager: WindowManager) {
        self.manager = manager
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            var hotkey = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            guard result == noErr, hotkey.id > 0, Int(hotkey.id) <= Command.allCases.count else { return OSStatus(eventNotHandledErr) }
            center.manager.execute(Command.allCases[Int(hotkey.id) - 1])
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        register()
    }

    func register() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        guard !suspended else { return }
        var failures: [String] = []
        for (index, command) in Command.allCases.enumerated() {
            let shortcut = manager.preferences.shortcut(command)
            guard shortcut.modifiers != 0 else { continue }
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x51554C54, id: UInt32(index + 1))
            let error = RegisterEventHotKey(shortcut.key, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
            if error == noErr, let reference { refs.append(reference) }
            else { failures.append(shortcut.label) }
        }
        manager.shortcutError = failures.isEmpty ? "" : "Already in use by another app: \(failures.joined(separator: ", ")). Record different shortcuts."
    }
    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let onRecord: (Shortcut) -> Void
    let onRecording: (Bool) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        button.target = button
        button.action = #selector(RecorderButton.startRecording)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onRecord = onRecord
        button.onRecording = onRecording
        if !button.recording { button.title = shortcut.modifiers == 0 ? "Disabled" : shortcut.label }
    }
}

final class RecorderButton: NSButton {
    var recording = false
    var onRecord: ((Shortcut) -> Void)?
    var onRecording: ((Bool) -> Void)?
    private var oldTitle = ""
    override var acceptsFirstResponder: Bool { true }

    @objc func startRecording() {
        guard !recording else { return }
        oldTitle = title
        recording = true
        title = "Press shortcut…"
        onRecording?(true)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        if event.keyCode == 51 { onRecord?(Shortcut(key: 0, modifiers: 0, label: "Disabled")); finish(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else { NSSound.beep(); return }
        var mask: UInt32 = 0, prefix = ""
        if flags.contains(.control) { mask |= UInt32(controlKey); prefix += "⌃" }
        if flags.contains(.option) { mask |= UInt32(optionKey); prefix += "⌥" }
        if flags.contains(.shift) { mask |= UInt32(shiftKey); prefix += "⇧" }
        if flags.contains(.command) { mask |= UInt32(cmdKey); prefix += "⌘" }
        let names: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 49: "Space", 36: "Return", 48: "Tab"]
        let name = names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "\(event.keyCode)"
        onRecord?(Shortcut(key: UInt32(event.keyCode), modifiers: mask, label: prefix + name))
        finish()
    }
    private func finish() {
        recording = false
        title = oldTitle
        onRecording?(false)
    }
    override func resignFirstResponder() -> Bool {
        if recording { finish() }
        return super.resignFirstResponder()
    }
}
