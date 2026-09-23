import AppKit
import Carbon
import Sparkle
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
    private var zoom: WindowZoom!
    private var swap: WindowSwap!
    private var updater: SPUStandardUpdaterController?
    private var quickAdd: QuickAddController!
    private var quickAddHotkey: GridHotKey!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSWindow.allowsAutomaticWindowTabbing = false
        manager = WindowManager(preferences: Preferences(), backgroundArrangements: false)
        overlay = GridOverlayController(manager: manager)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.toolTip = "Tilez · ⌃⌥Space"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleGrid)
        hotkey = GridHotKey { [weak self] in self?.showGrid() }
        zoom = WindowZoom()
        swap = WindowSwap()
        swap.isExcluded = { [weak self] in self?.zoom.isEnlarged($0) ?? false }
        quickAdd = QuickAddController(manager: manager)
        quickAddHotkey = GridHotKey(keyCode: kVK_ANSI_N, id: 3) { [weak self] in self?.showQuickAdd() }
        // Only release builds carry an update feed; builds from source update with scripts/update.sh.
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            overlay.model.onCheckForUpdates = { [weak self] in
                self?.overlay.close(restoreFocus: false)
                NSApp.activate(ignoringOtherApps: true)
                self?.updater?.checkForUpdates(nil)
            }
        }
        configureMainMenu()
        // A small first-run introduction is the actual grid, with permission inline if needed.
        if !UserDefaults.standard.bool(forKey: "hasOpenedGridV2") || CommandLine.arguments.contains("--show-grid") {
            overlay.show()
            UserDefaults.standard.set(true, forKey: "hasOpenedGridV2")
        }
        if !hotkey.registered {
            overlay.model.message = "⌃⌥Space is already in use. Open Tilez from its menu-bar icon."
            overlay.model.isError = true
        } else if !zoom.hotkey.registered {
            overlay.model.message = "⌃⌥Return is already in use, so windows can’t be enlarged with it."
            overlay.model.isError = true
        } else if !quickAddHotkey.registered {
            overlay.model.message = "⌃⌥N is already in use, so Quick Add is unavailable."
            overlay.model.isError = true
        }
    }
    /// Template artwork follows the app icon's three panes and adapts to the menu bar.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            for rect in [NSRect(x: 1, y: 12, width: 16, height: 5),
                         NSRect(x: 1, y: 1, width: 7, height: 9),
                         NSRect(x: 10, y: 1, width: 7, height: 9)] {
                NSBezierPath(roundedRect: rect, xRadius: 1.2, yRadius: 1.2).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tilez"
        return image
    }
    /// Quick Add opens where the grid would, after that screen's enlarged window returns to its pane.
    private func showQuickAdd() {
        if quickAdd.isShown { quickAdd.close(); return }
        if overlay.isShown { overlay.model.cancel(); overlay.close(restoreFocus: false) }
        guard let target = overlay.targetScreen(nil), let display = Display.all.first(where: { $0.screen == target }) else { return }
        guard zoom.hasEnlarged(on: display) else { quickAdd.show(on: display); return }
        Task { await zoom.restore(on: display); quickAdd.show(on: display) }
    }
    @objc private func toggleGrid() { showGrid(on: statusItem.button?.window?.screen) }
    /// That screen's enlarged window returns to its pane first so the grid captures the real layout.
    private func showGrid(on screen: NSScreen? = nil) {
        quickAdd.close()
        let target = overlay.targetScreen(screen)
        guard !overlay.isShown, let display = Display.all.first(where: { $0.screen == target }),
              zoom.hasEnlarged(on: display) else { overlay.toggle(on: target); return }
        Task { await zoom.restore(on: display); overlay.toggle(on: target) }
    }
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
    func applicationWillTerminate(_ notification: Notification) {
        zoom.restoreBeforeQuit()
        overlay.model.cancel(); overlay.model.persist()
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
