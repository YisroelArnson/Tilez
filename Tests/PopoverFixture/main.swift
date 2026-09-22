import AppKit
import SwiftUI
import TilezCore

private final class FixtureModel: ObservableObject {
    @Published var rows = 2
}

private struct FixtureContent: View {
    @ObservedObject var model: FixtureModel
    var body: some View {
        VStack(spacing: 16) {
            Text("Popover regression check").font(.headline)
            ScrollView {
                LazyVStack { ForEach(0..<model.rows, id: \.self) { Text("Test setup \($0 + 1)").frame(height: 48) } }
            }
            Text("Bottom action remains on screen")
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class Fixture: NSObject, NSApplicationDelegate {
    let model = FixtureModel()
    var anchorPanel: NSPanel!
    var controller: MenuPopoverController<FixtureContent>!
    var reports: [[String: Any]] = []
    var step = 0
    var controlWindow: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        controller = MenuPopoverController(rootView: FixtureContent(model: model))
        controlWindow = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 340, height: 140),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controlWindow.title = "Popover regression"
        controlWindow.isReleasedWhenClosed = false
        let button = NSButton(title: "Run native popover checks", target: self, action: #selector(start))
        button.frame = CGRect(x: 30, y: 50, width: 280, height: 36)
        controlWindow.contentView?.addSubview(button)
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func start() {
        let screen = controlWindow.screen ?? NSScreen.main!
        // A menu-bar-sized anchor at the top of the real display. This avoids
        // depending on spare space in the user's crowded system status bar.
        anchorPanel = NSPanel(contentRect: CGRect(x: screen.visibleFrame.maxX - 300, y: screen.visibleFrame.maxY - 27, width: 22, height: 27),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        anchorPanel.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 22, height: 27))
        anchorPanel.orderFront(nil)
        controlWindow.orderOut(nil)
        runStep()
    }
    func runStep() {
        guard let button = anchorPanel.contentView, let screen = anchorPanel.screen else { finish(error: "No anchor display"); return }
        let arranging = step == 1
        model.rows = arranging ? 40 : 2
        let size = MenuPanelGeometry.contentSize(arranging: arranging, setupCount: 2, needsPermission: false, visibleFrame: screen.visibleFrame)
        if step == 0 || step == 3 { controller.show(relativeTo: button, contentSize: size) }
        else { controller.resize(to: size) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = self.controller.window else { self.finish(error: "No popover window"); return }
            let frame = window.frame
            let fits = screen.visibleFrame.contains(frame)
            self.reports.append(["step": self.step, "fits": fits, "height": frame.height, "width": frame.width])
            guard fits else { self.finish(error: "Popover extends off screen at step \(self.step): \(frame)"); return }
            self.step += 1
            if self.step == 3 { self.controller.close() }
            if self.step < 4 { self.runStep() } else { self.finish(error: nil) }
        }
    }
    func finish(error: String?) {
        let report: [String: Any] = ["passed": error == nil, "error": error ?? "", "checks": reports]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: URL(fileURLWithPath: "/private/tmp/tilez-popover-check/native-regression.json"), options: .atomic)
        controller?.close()
        anchorPanel?.orderOut(nil)
        controlWindow.contentView?.subviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(wrappingLabelWithString: error ?? "PASS: opened, expanded, shrank, and reopened on screen")
        label.frame = CGRect(x: 20, y: 20, width: 300, height: 90)
        controlWindow.contentView?.addSubview(label)
        controlWindow.makeKeyAndOrderFront(nil)
    }
}
let app = NSApplication.shared
private let delegate = Fixture()
app.delegate = delegate
app.run()
