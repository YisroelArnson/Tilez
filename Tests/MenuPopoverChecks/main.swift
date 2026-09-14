import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
status.button!.title = "+"
let picker = MenuPopoverController(rootView: Text("Popover dismissal check").padding())
var finished = false
func finish(_ passed: Bool, _ message: String) {
    guard !finished else { return }
    finished = true
    print("\(passed ? "PASS" : "FAIL"): \(message)")
    picker.close()
    NSStatusBar.system.removeStatusItem(status)
    exit(passed ? 0 : 1)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    app.activate(ignoringOtherApps: true)
    picker.show(relativeTo: status.button!, contentSize: CGSize(width: 300, height: 150))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
        guard picker.isShown else { finish(false, "popover must be open before switching apps"); return }
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            finish(false, "Finder must be running for this native check"); return
        }
        finder.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
                finish(false, "Finder did not activate"); return
            }
            finish(!picker.isShown, "popover closes when another app activates")
        }
    }
}
app.run()
finish(false, "AppKit event loop did not start; run this check in a desktop session")
