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
    private var realignHotkey: GridHotKey!
    private var workspaces: WorkspaceStore!
    private var workspacePanel: WorkspacePanelController!
    private var workspaceHotkeys: [GridHotKey] = []
    private var numberHotkeys: [GridHotKey] = []
    private let updateReminder = UpdateReminder()

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
        zoom.onDragBegan = { [weak self] in self?.swap.begin(at: $0) }
        zoom.onDragMoved = { [weak self] in self?.swap.move(to: $0) }
        zoom.onDragEnded = { [weak self] in self?.swap.end() }
        quickAdd = QuickAddController(manager: manager)
        quickAddHotkey = GridHotKey(keyCode: kVK_ANSI_N, id: 3) { [weak self] in self?.showQuickAdd() }
        realignHotkey = GridHotKey(keyCode: kVK_ANSI_R, id: 4) { [weak self] in self?.realign() }
        workspaces = WorkspaceStore(manager: manager)
        overlay.model.workspaces = workspaces
        quickAdd.workspaces = workspaces
        workspacePanel = WorkspacePanelController(store: workspaces)
        workspacePanel.prepare = { [weak self] display in
            guard let zoom = self?.zoom, zoom.hasEnlarged(on: display) else { return }
            await zoom.restore(on: display)
        }
        overlay.model.onOpenWorkspace = { [weak self] workspace in
            guard let self else { return }
            let display = self.overlay.model.display
            self.overlay.close(restoreFocus: false)
            self.workspacePanel.open(workspace, on: display)
        }
        overlay.model.onRenameWorkspace = { [weak self] workspace in
            guard let self, let display = self.overlay.model.display else { return }
            self.overlay.close(restoreFocus: false)
            self.workspacePanel.showRename(workspace.id, on: display)
        }
        // ⌃⌥1–9 switch to the workspace at that position in the list.
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        numberHotkeys = digits.enumerated().map { index, key in
            GridHotKey(keyCode: key, id: UInt32(11 + index)) { [weak self] in self?.openWorkspace(number: index + 1) }
        }
        workspaceHotkeys = [
            GridHotKey(keyCode: kVK_ANSI_W, id: 5) { [weak self] in self?.showWorkspaces { $0.showList(on: $1) } },
            GridHotKey(keyCode: kVK_ANSI_S, id: 6) { [weak self] in self?.showWorkspaces { $0.quickSave(on: $1) } },
            GridHotKey(keyCode: kVK_ANSI_S, id: 7, modifiers: controlKey | optionKey | shiftKey) { [weak self] in
                self?.showWorkspaces { $0.showSave(on: $1) }
            },
        ]
        // Only release builds carry an update feed; builds from source update with scripts/update.sh.
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            updateReminder.onChange = { [weak self] version in
                self?.overlay.model.availableUpdate = version
                self?.overlay.model.updateReady = self?.updateReminder.install != nil
            }
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updateReminder, userDriverDelegate: updateReminder)
            overlay.model.onCheckForUpdates = { [weak self] in
                self?.overlay.close(restoreFocus: false)
                NSApp.activate(ignoringOtherApps: true)
                self?.updater?.checkForUpdates(nil)
            }
            overlay.model.onUpdate = { [weak self] in
                if let install = self?.updateReminder.install { install() } else { self?.overlay.model.onCheckForUpdates?() }
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
        } else if !realignHotkey.registered {
            overlay.model.message = "⌃⌥R is already in use, so windows can’t be realigned with it."
            overlay.model.isError = true
        } else if let taken = zip(["⌃⌥W", "⌃⌥S", "⌃⌥⇧S"] + (1...9).map { "⌃⌥\($0)" }, workspaceHotkeys + numberHotkeys)
                    .first(where: { !$0.1.registered })?.0 {
            overlay.model.message = "\(taken) is already in use. Open and save workspaces from the grid’s Save menu."
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
        workspacePanel.close()
        if overlay.isShown { overlay.model.cancel(); overlay.close(restoreFocus: false) }
        guard let target = overlay.targetScreen(nil), let display = Display.all.first(where: { $0.screen == target }) else { return }
        guard zoom.hasEnlarged(on: display) else { quickAdd.show(on: display); return }
        Task { await zoom.restore(on: display); quickAdd.show(on: display) }
    }
    /// Workspace shortcuts act on the screen the grid would open on, never while the grid is editing.
    /// Pressing the panel's own shortcut again closes it; a number switches even while it's open.
    private func showWorkspaces(toggles: Bool = true, _ action: (WorkspacePanelController, Display) -> Void) {
        if workspacePanel.isShown {
            workspacePanel.close(restoreFocus: toggles)
            if toggles { return }
        }
        if overlay.isShown { overlay.model.cancel(); overlay.close(restoreFocus: false) }
        quickAdd.close()
        guard let target = overlay.targetScreen(nil), let display = Display.all.first(where: { $0.screen == target }) else { return }
        action(workspacePanel, display)
    }
    private func openWorkspace(number: Int) {
        guard let workspace = workspaces.workspace(number: number) else { NSSound.beep(); return }
        showWorkspaces(toggles: false) { panel, display in panel.open(workspace, on: display) }
    }
    /// With the grid open this tidies its panes; otherwise the screen's windows move directly,
    /// after an enlarged window returns to its pane.
    private func realign() {
        if overlay.isShown { overlay.model.realign(); return }
        quickAdd.close()
        guard let target = overlay.targetScreen(nil), let display = Display.all.first(where: { $0.screen == target }) else { return }
        Task {
            if zoom.hasEnlarged(on: display) { await zoom.restore(on: display) }
            await WindowRealign.run(on: display, manager: manager)
        }
    }
    @objc private func toggleGrid() { showGrid(on: statusItem.button?.window?.screen) }
    /// That screen's enlarged window returns to its pane first so the grid captures the real layout.
    private func showGrid(on screen: NSScreen? = nil) {
        quickAdd.close()
        workspacePanel.close()
        // Opening the grid also checks for updates if it has been a while, so the pill appears promptly.
        if !overlay.isShown, let updater = updater?.updater, updater.canCheckForUpdates,
           (updater.lastUpdateCheckDate ?? .distantPast) < Date().addingTimeInterval(-3600) {
            updater.checkForUpdatesInBackground()
        }
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

/// Scheduled update checks show as a pill in the grid instead of an alert over whatever you're
/// doing; the pill's Update button opens Sparkle's usual update window. With automatic updates on,
/// Sparkle downloads silently and would wait for you to quit; the pill's Restart installs it now.
@MainActor final class UpdateReminder: NSObject, @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    var onChange: ((String?) -> Void)?
    private(set) var install: (() -> Void)?
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        install = immediateInstallHandler
        onChange?(item.displayVersionString)
        return true
    }
    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { onChange?(update.displayVersionString) }
    }
    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { onChange?(nil) }
    // A downloaded update keeps its pill until you restart into it.
    func standardUserDriverWillFinishUpdateSession() { if install == nil { onChange?(nil) } }
}
