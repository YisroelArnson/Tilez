import AppKit

final class Fixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var windows: [NSWindow] = []
    var nextID = 1
    let inheritedFullScreen = CommandLine.arguments.contains("--full-screen")
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Tilez Active Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu; bar.addItem(appItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        let new = NSMenuItem(title: "New Window", action: #selector(newWindow), keyEquivalent: "n")
        new.target = self
        file.addItem(new); fileItem.submenu = file; bar.addItem(fileItem)
        NSApp.mainMenu = bar
        newWindow()
        if !inheritedFullScreen { newWindow() }
        if CommandLine.arguments.contains("--minimized") { windows.last?.miniaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.report() }
    }
    @objc func newWindow() {
        let w = NSWindow(contentRect: CGRect(x: 100 + nextID * 35, y: 150 + nextID * 35, width: 450, height: 320),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.tabbingMode = .disallowed
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.title = "Tilez test window \(nextID)"
        w.minSize = CGSize(width: 100, height: 100)
        w.isReleasedWhenClosed = false
        w.delegate = self
        let label = NSTextField(labelWithString: "Blank test window \(nextID)")
        label.font = .systemFont(ofSize: 24)
        label.frame = CGRect(x: 30, y: 100, width: 380, height: 50)
        w.contentView?.addSubview(label)
        windows.append(w); nextID += 1
        w.makeKeyAndOrderFront(nil)
        if inheritedFullScreen { w.toggleFullScreen(nil) }
        report()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if FileManager.default.fileExists(atPath: "/private/tmp/tilez-active-fixture/block-close") {
            let alert = NSAlert()
            alert.messageText = "Test save confirmation"
            alert.informativeText = "The fixture is deliberately refusing to close this window."
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: sender) { _ in }
            return false
        }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        windows.removeAll { $0 === notification.object as? NSWindow }
    }
    func report() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
        typealias Connection = @convention(c) () -> Int32
        typealias Membership = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
        let connection = unsafeBitCast(dlsym(handle, "SLSMainConnectionID")!, to: Connection.self)()
        let membership = unsafeBitCast(dlsym(handle, "SLSCopySpacesForWindows")!, to: Membership.self)
        let frames = windows.map { window -> [String: Any] in
            let spaces = membership(connection, 7, [NSNumber(value: window.windowNumber)] as CFArray)?.takeRetainedValue() as? [NSNumber] ?? []
            return ["title": window.title, "number": window.windowNumber, "spaces": spaces, "fullScreen": window.styleMask.contains(.fullScreen), "minimized": window.isMiniaturized,
                    "x": window.frame.minX, "y": window.frame.minY, "w": window.frame.width, "h": window.frame.height]
        }
        let data = try! JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
        try? data.write(to: URL(fileURLWithPath: "/private/tmp/tilez-active-fixture/windows.json"), options: .atomic)
    }
}
let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.run()
