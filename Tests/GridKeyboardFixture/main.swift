import AppKit
import Combine
import TilezCore

// Uses the production overlay and key routing with isolated, in-memory drafts.
final class KeyboardFixtureDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

@MainActor final class KeyboardFixtureDelegate: NSObject, NSApplicationDelegate {
    private var overlay: GridOverlayController!
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.show(on: NSScreen.main)
        return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let storage = KeyboardFixtureDefaults(suiteName: nil)!
        let manager = WindowManager(preferences: Preferences(defaults: storage), backgroundArrangements: false)
        overlay = GridOverlayController(manager: manager, defaults: storage)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        item.submenu = NSMenu()
        item.submenu?.addItem(withTitle: "Quit Keyboard Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        edit.submenu = editMenu; menu.addItem(edit)
        NSApp.mainMenu = menu
        overlay.show(on: NSScreen.main)
        overlay.model.grid = DesktopGrid(slots: [
            GridSlot(app: GridApp(bundleID: "com.apple.Safari", name: "Safari")),
            GridSlot(app: GridApp(bundleID: "com.apple.finder", name: "Finder"))
        ])
        overlay.model.selectedCell = 0
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = KeyboardFixtureDelegate()
    app.delegate = delegate
    app.run()
}
