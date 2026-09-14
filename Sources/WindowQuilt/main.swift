import AppKit
import SwiftUI
import QuiltCore

final class ActionItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("Not supported") }
    @objc private func invoke() { handler() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let preferences = Preferences()
    private var manager: WindowManager!
    private var hotkeys: HotKeyCenter!
    private var overlays: OverlayController!
    private var window: NSWindow?
    private let navigation = QuiltNavigation()
    private var popover: MenuPopoverController<QuiltPopoverView>!
    private var popoverShowsArrangement = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        manager = WindowManager(preferences: preferences)
        hotkeys = HotKeyCenter(manager: manager)
        overlays = OverlayController(manager: manager)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Window Quilt")
        statusItem.button?.toolTip = "Window Quilt — arrange your windows"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popoverShowsArrangement = preferences.setups.isEmpty
        popover = MenuPopoverController(rootView:
            QuiltPopoverView(manager: manager, preferences: preferences, navigation: navigation, openWindow: { [weak self] page in
                self?.navigation.page = page
                self?.popover.close()
                self?.showWindow()
            }, arrangementChanged: { [weak self] arranging in
                self?.popoverShowsArrangement = arranging
                // Finish the SwiftUI state update before resizing its hosting view.
                DispatchQueue.main.async { self?.resizePopover() }
            }))
        manager.onPermissionChange = { [weak self] in
            self?.hotkeys.register()
            self?.overlays.installMonitors()
        }
        if !UserDefaults.standard.bool(forKey: "hasOpened") || !manager.trusted {
            showWindow()
            UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.close(); return }
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            navigation.preferredApp = app.bundleIdentifier
        }
        manager.refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button, contentSize: popoverSize())
    }

    private func popoverSize() -> CGSize {
        let visibleFrame = statusItem.button?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        return MenuPanelGeometry.contentSize(arranging: popoverShowsArrangement, setupCount: preferences.setups.count,
                                             needsPermission: !manager.trusted, visibleFrame: visibleFrame,
                                             activeLayoutCount: manager.runningLayouts.count)
    }

    private func resizePopover() { popover.resize(to: popoverSize()) }

    func showWindow() {
        if window == nil {
            let content = QuiltView(manager: manager, preferences: preferences, navigation: navigation, hotkeys: hotkeys)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 700),
                               styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            win.title = "Window Quilt"
            win.titlebarAppearsTransparent = true
            win.contentView = NSHostingView(rootView: content)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    private func configureMainMenu() {
        let bar = NSMenu()
        let application = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(ActionItem("About Window Quilt") { [weak self] in self?.showWindow() })
        applicationMenu.addItem(ActionItem("Show menu-bar picker") { [weak self] in self?.togglePopover() })
        applicationMenu.addItem(NSMenuItem(title: "Quit Window Quilt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        application.submenu = applicationMenu
        bar.addItem(application)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        edit.submenu = editMenu
        bar.addItem(edit)
        NSApp.mainMenu = bar
    }
    func windowWillClose(_ notification: Notification) { hotkeys.suspended = false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
