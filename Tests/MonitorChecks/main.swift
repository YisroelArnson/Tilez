import Foundation
import TilezCore

var failures = 0
var checks = 0
func expect<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    checks += 1
    if actual == expected {
        print("PASS: \(message)")
    } else {
        failures += 1
        print("FAIL: \(message); expected \(expected), got \(actual)")
    }
}

let screens: Set<String> = ["Laptop", "External"]
func destination(explicit: String? = nil, visibleGrid: String? = nil, pointer: String? = nil,
                 activeWindow: String? = nil, fallback: String? = "Laptop", connected: Set<String> = screens) -> String? {
    ScreenDestination.choose(explicit: explicit, visibleGrid: visibleGrid, pointer: pointer,
                             activeWindow: activeWindow, fallback: fallback, connected: connected)
}

expect(destination(pointer: "External", activeWindow: "Laptop"), "External", "Pointer selects external despite active laptop window")
expect(destination(explicit: "Laptop", visibleGrid: "External", pointer: "External"), "Laptop", "Explicit destination wins")
let captured = destination(visibleGrid: "External", pointer: "Laptop", activeWindow: "Laptop")
expect(destination(explicit: captured, pointer: "Laptop", activeWindow: "Laptop"), "External", "Captured visible-grid destination survives dismissal")
expect(destination(activeWindow: "External"), "External", "Missing pointer falls back to active window")
expect(destination(), "Laptop", "Missing pointer and active window fall back to main screen")
expect(destination(explicit: "Gone", visibleGrid: "Gone", pointer: "External", activeWindow: "Laptop"), "External", "Disconnected destinations are ignored")
expect(destination(explicit: "Gone", fallback: "Gone", connected: []), nil, "No connected screen means no destination")

let binding = GridWindowBinding(windowID: "42:window-7", processSession: "session")
let pane = GridSlot(app: GridApp(bundleID: "test.editor", name: "Editor"), binding: binding)
let frame = CGRect(x: 0.15, y: 0.2, width: 0.5, height: 0.6)
let grid = DesktopGrid(panes: [pane], frames: [frame])

func recordIfSettled(_ memory: inout ScreenMemory, transition: ScreenTransition, pending: Set<String>,
                     connected: Set<String> = screens, on display: String) {
    guard transition.permitsRecording, pending.isEmpty, connected.count > 1 else { return }
    memory.record(grid, on: display)
}

do {
    var memory = ScreenMemory()
    memory.record(grid, on: "External", desktops: [binding: "external-desktop"])
    var transition = ScreenTransition(connected: screens)
    transition.sleep(remembered: Set(memory.screens.keys))
    transition.wake()
    transition.screensChanged()
    let change = transition.settle(on: screens)
    let pending = (change?.recover ?? []).intersection(memory.screens.keys)
    expect(pending, ["External"], "Same-ID wake enrolls the remembered screen before recording")
    recordIfSettled(&memory, transition: transition, pending: pending, on: "Laptop")
    expect(memory.displaced(from: "External", location: { _ in "Laptop" })?.slots.compactMap(\.binding),
           [binding], "Post-wake recording preserves the external window's ownership")
    expect(memory.screens["External"]?.first?.frame, frame, "Wake preserves the original pane geometry")
    expect(memory.screens["External"]?.first?.desktop, "external-desktop", "Wake preserves the original desktop")
    transition.screensChanged()
    expect(transition.settle(on: screens)?.recover, [], "A settled wake baseline is consumed only once")
}

do {
    var memory = ScreenMemory()
    memory.record(grid, on: "External")
    var transition = ScreenTransition(connected: screens)
    transition.sleep(remembered: Set(memory.screens.keys))
    transition.screensChanged()
    expect(transition.settle(on: ["Laptop"]) == nil, true, "Screen notifications cannot settle while asleep")
    expect(transition.permitsRecording, false, "Screen notifications while asleep keep recording frozen")
    recordIfSettled(&memory, transition: transition, pending: [], on: "Laptop")
    expect(memory.screens["External"]?.first?.slot.binding, binding, "Asleep notifications preserve remembered ownership")
    transition.wake()
    transition.screensChanged()
    transition.screensChanged()
    expect(transition.settle(on: screens)?.recover, ["External"], "Repeated notifications retain the wake recovery baseline")
}

do {
    var transition = ScreenTransition(connected: screens)
    transition.sleep(remembered: ["External"])
    transition.sleep(remembered: [])
    transition.wake()
    transition.wake()
    transition.screensChanged()
    expect(transition.settle(on: screens)?.recover, ["External"], "Repeated sleep and wake retain the first baseline")
    transition.wake()
    transition.screensChanged()
    expect(transition.settle(on: screens)?.recover, [], "A repeated wake cannot restore the consumed baseline")
}

do {
    var memory = ScreenMemory()
    memory.record(grid, on: "External")
    var transition = ScreenTransition(connected: screens)
    recordIfSettled(&memory, transition: transition, pending: [], on: "Laptop")
    transition.screensChanged()
    let change = transition.settle(on: screens)
    expect(change?.recover, [], "A resolution-only change does not request recovery")
    expect(memory.screens["Laptop"]?.first?.slot.binding, binding, "Resolution change preserves an intentional window move")
    transition.sleep(remembered: Set(memory.screens.keys))
    transition.wake()
    transition.screensChanged()
    let wake = transition.settle(on: screens)
    let pending = (wake?.recover ?? []).intersection(memory.screens.keys)
    expect(pending, ["Laptop"], "Pre-sleep intentional move becomes the recovery destination")
    recordIfSettled(&memory, transition: transition, pending: pending, on: "External")
    expect(memory.displaced(from: "Laptop", location: { _ in "External" })?.slots.compactMap(\.binding),
           [binding], "Wake restores the intentional pre-sleep owner")
}

do {
    var memory = ScreenMemory()
    memory.record(grid, on: "External")
    var transition = ScreenTransition(connected: screens)
    transition.screensChanged()
    let disconnected = transition.settle(on: ["Laptop"])
    expect(disconnected?.removed, ["External"], "A real disconnect identifies the removed screen")
    expect(disconnected?.recover, [], "An absent screen is not a restore destination")
    recordIfSettled(&memory, transition: transition, pending: [], connected: ["Laptop"], on: "Laptop")
    transition.screensChanged()
    let returned = transition.settle(on: screens)
    let pending = (returned?.recover ?? []).intersection(memory.screens.keys)
    expect(pending, ["External"], "A real reconnect still enrolls the remembered screen")
    recordIfSettled(&memory, transition: transition, pending: pending, on: "Laptop")
    expect(memory.displaced(from: "External", location: { _ in "Laptop" })?.slots.compactMap(\.binding),
           [binding], "Reconnect preserves displaced ownership until recovery")
}

do {
    var transition = ScreenTransition(connected: screens)
    transition.sleep(remembered: ["External"])
    transition.wake()
    transition.screensChanged()
    expect(transition.settle(on: ["Laptop"])?.recover, [], "A screen still absent after wake cannot receive windows")
    transition.screensChanged()
    expect(transition.settle(on: screens)?.recover, ["External"], "An absent wake screen can recover on later reconnect")
}

print("\(checks - failures)/\(checks) monitor checks passed")
exit(failures == 0 ? 0 : 1)
