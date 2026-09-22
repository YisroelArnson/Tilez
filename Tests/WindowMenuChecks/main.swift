import AppKit
import TilezCore

// A disposable AppKit app with Terminal's nested New Window menu shape.
// It opens plain test windows, never a shell or a user's document.
@MainActor final class WindowMenuFixture: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bar = NSMenu()
        let appItem = NSMenuItem(title: "Menu Fixture", action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu()
        appItem.submenu!.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        bar.addItem(appItem)
        let shell = NSMenuItem(title: "Shell", action: nil, keyEquivalent: "")
        shell.submenu = NSMenu()
        bar.addItem(shell)
        let newWindow = NSMenuItem(title: "New Window", action: nil, keyEquivalent: "")
        let profiles = NSMenu()
        newWindow.submenu = profiles
        shell.submenu!.addItem(newWindow)
        let other = NSMenuItem(title: "Other profile", action: #selector(wrongProfile), keyEquivalent: "")
        other.target = self
        profiles.addItem(other)
        let basic = NSMenuItem(title: "New Window with Profile – Basic", action: #selector(openWindow), keyEquivalent: "n")
        basic.target = self
        profiles.addItem(basic)
        NSApp.mainMenu = bar
        openWindow()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func wrongProfile() { fatalError("Selected an arbitrary profile instead of the default") }
    @objc func openWindow() {
        let window = NSWindow(contentRect: CGRect(x: 80 + windows.count * 40, y: 80, width: 320, height: 180),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Tilez menu test \(windows.count + 1)"
        windows.append(window)
        window.orderFront(nil)
    }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe", let pid = Int32(CommandLine.arguments[2]) {
    var finished = false
    Task { @MainActor in
        do {
            let ids = try await WindowCount.prepare(target: 3, current: {
                try await Accessibility.perform {
                    let app = AXUIElementCreateApplication(pid)
                    let windows = Accessibility.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
                    return windows.map { String(CFHash($0)) }
                }
            }, requestNew: {
                guard let command = try await Accessibility.perform({ Accessibility.newWindowCommand(pid: pid) }) else {
                    throw NSError(domain: "MenuFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "AX did not resolve the profile command"])
                }
                let title = try await Accessibility.perform { Accessibility.value(command, kAXTitleAttribute) as? String }
                assert(title == "New Window with Profile – Basic", "Must select the default profile action")
                let result = try await Accessibility.perform { AXUIElementPerformAction(command, kAXPressAction as CFString) }
                assert(result == .success, "Profile action must be accepted")
            }, wait: { try await Task.sleep(nanoseconds: 20_000_000) }, pollsPerWindow: 50)
            assert(ids.count == 3 && Set(ids).count == 3)
            print("PASS: production AX traversal opens two distinct AppKit windows through a profile submenu")
            finished = true
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
    let deadline = Date().addingTimeInterval(10)
    while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    assert(finished, "Native menu check timed out")
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = WindowMenuFixture()
        app.delegate = delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(1) }
        app.run()
    }
}
