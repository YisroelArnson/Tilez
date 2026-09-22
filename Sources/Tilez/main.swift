import AppKit
import SwiftUI

final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self; isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("Not supported") }
    @objc private func invoke() { handler() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var manager: WindowManager!
    private var overlay: GridOverlayController!
    private var hotkey: GridHotKey!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false
        manager = WindowManager(preferences: Preferences(), backgroundArrangements: false)
        overlay = GridOverlayController(manager: manager)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Tilez")
        statusItem.button?.toolTip = "Tilez · ⌃⌥Space"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleGrid)
        hotkey = GridHotKey { [weak self] in self?.overlay.toggle() }
        configureMainMenu()
        // A small first-run introduction is the actual grid, with permission inline if needed.
        if !UserDefaults.standard.bool(forKey: "hasOpenedGridV2") || CommandLine.arguments.contains("--show-grid") {
            overlay.show()
            UserDefaults.standard.set(true, forKey: "hasOpenedGridV2")
        }
        if !hotkey.registered {
            overlay.model.message = "⌃⌥Space is already in use. Open Tilez from its menu-bar icon."
            overlay.model.isError = true
        }
    }
    @objc private func toggleGrid() { overlay.toggle(on: statusItem.button?.window?.screen) }
    private func configureMainMenu() {
        let bar = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(ActionItem("Show Tilez") { [weak self] in self?.overlay.toggle() })
        appMenu.addItem(NSMenuItem(title: "Quit Tilez", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        app.submenu = appMenu; bar.addItem(app)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            menu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        edit.submenu = menu; bar.addItem(edit)
        NSApp.mainMenu = bar
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.show(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { overlay.model.cancel(); overlay.model.persist() }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
