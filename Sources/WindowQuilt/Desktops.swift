import AppKit
import ApplicationServices
import QuiltSpacesBridge

struct Desktop: Identifiable, Equatable {
    let number: UInt64
    let uuid: String
    let displayID: String
    let displayNumber: UInt32
    let index: Int
    let isCurrent: Bool
    let displayName: String
    var isFullScreen = false
    var id: String { "\(displayID)|\(uuid.isEmpty ? "session-\(number)" : uuid)" }
    var title: String { "Desktop \(index) · \(displayName)" + (isCurrent ? " (current)" : "") }
}

enum DesktopError: LocalizedError {
    case unavailable, missingDesktop, missionControl, creationFailed, moveFailed, switchFailed, missingDisplay
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Desktop control is unavailable on this macOS version. Your existing windows have not been moved."
        case .missingDesktop: return "The saved desktop no longer exists. Edit this setup and choose another desktop."
        case .missionControl: return "Quilt could not access Mission Control. Close Mission Control and try again."
        case .creationFailed: return "macOS did not create a desktop. You may have reached its desktop limit."
        case .moveFailed: return "macOS did not move every window to the requested desktop. Quilt stopped before tiling."
        case .switchFailed: return "Quilt could not confirm the desktop switch. Open Mission Control to select the desktop."
        case .missingDisplay: return "The setup’s display is disconnected. Edit the setup to choose an available display."
        }
    }
}

enum Desktops {
    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let processLibrary = dlopen(nil, RTLD_LAZY)
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopyDisplays = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias WindowNumber = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32

    private static func symbol<T>(_ name: String, _ type: T.Type) -> T? {
        guard let library, let pointer = dlsym(library, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }
    private static var connection: Int32? { symbol("SLSMainConnectionID", Connection.self)?() }
    static var canMove: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0)) && QuiltCanMoveToSpace()
    }
    static func windowNumber(_ window: AXUIElement) -> UInt32? {
        guard let handle = processLibrary, let pointer = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        let call = unsafeBitCast(pointer, to: WindowNumber.self)
        var number: UInt32 = 0
        guard call(window, &number) == 0, number != 0 else { return nil }
        return number
    }
    static func existingWindowNumbers(pid: pid_t) -> Set<UInt32> {
        let records = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(records.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }
    static func spaces(for number: UInt32) -> Set<UInt64> {
        guard let connection, let call = symbol("SLSCopySpacesForWindows", CopyWindowSpaces.self),
              let array = call(connection, 7, [NSNumber(value: number)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return Set(array.map(\.uint64Value))
    }
    static func all(includeFullScreen: Bool = false) -> [Desktop] {
        guard let connection, let call = symbol("SLSCopyManagedDisplaySpaces", CopyDisplays.self),
              let array = call(connection)?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result: [Desktop] = []
        for record in array {
            let identifier = record["Display Identifier"] as? String ?? ""
            guard let display = Display.all.first(where: { $0.id.caseInsensitiveCompare(identifier) == .orderedSame })
                ?? (array.count == 1 ? Display.all.first : nil) else { continue }
            let screenNumber = (display.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let current = record["Current Space"] as? [String: Any] ?? [:]
            let currentID = (current["ManagedSpaceID"] as? NSNumber ?? current["id64"] as? NSNumber)?.uint64Value
            let spaces = record["Spaces"] as? [[String: Any]] ?? []
            for (index, space) in spaces.enumerated() {
                guard ((space["type"] as? NSNumber)?.intValue == 0 || (includeFullScreen && (space["type"] as? NSNumber)?.intValue == 4)),
                      let number = (space["ManagedSpaceID"] as? NSNumber ?? space["id64"] as? NSNumber)?.uint64Value else { continue }
                result.append(Desktop(number: number, uuid: space["uuid"] as? String ?? "", displayID: display.id,
                                      displayNumber: screenNumber, index: index + 1, isCurrent: number == currentID, displayName: display.name, isFullScreen: (space["type"] as? NSNumber)?.intValue == 4))
            }
        }
        return result
    }
    static func current(displayID: String) -> Desktop? { all().first { $0.displayID == displayID && $0.isCurrent } }

    @MainActor static func resolve(_ selection: String, display: Display) async throws -> Desktop {
        if selection == "new" { return try await create(on: display) }
        if selection == "current" {
            guard let desktop = current(displayID: display.id) else { throw DesktopError.unavailable }
            return desktop
        }
        guard let desktop = all().first(where: { $0.id == selection }) else { throw DesktopError.missingDesktop }
        guard desktop.displayID == display.id else { throw DesktopError.missingDisplay }
        return desktop
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        Accessibility.value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private static func find(_ element: AXUIElement, identifier: String, depth: Int = 0) -> AXUIElement? {
        guard depth < 7 else { return nil }
        if Accessibility.value(element, kAXIdentifierAttribute) as? String == identifier { return element }
        for child in children(element) {
            if let found = find(child, identifier: identifier, depth: depth + 1) { return found }
        }
        return nil
    }
    private static func missionControl() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        return find(AXUIElementCreateApplication(dock.processIdentifier), identifier: "mc")
    }
    @MainActor private static func openMissionControl() async throws -> AXUIElement {
        if let mc = missionControl() { return mc }
        let path = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: path, configuration: configuration) { _, _ in }
        for _ in 0..<24 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let mc = missionControl() {
                try await Task.sleep(nanoseconds: 350_000_000)
                return mc
            }
        }
        throw DesktopError.missionControl
    }
    private static func subgroup(_ mc: AXUIElement, number: UInt32, identifier: String) -> AXUIElement? {
        let displays = children(mc).filter { Accessibility.value($0, kAXIdentifierAttribute) as? String == "mc.display" }
        guard let display = displays.first(where: { (Accessibility.value($0, "AXDisplayID") as? NSNumber)?.uint32Value == number })
                ?? (displays.count == 1 ? displays.first : nil) else { return nil }
        return find(display, identifier: identifier)
    }
    @MainActor static func create(on display: Display) async throws -> Desktop {
        guard canMove else { throw DesktopError.unavailable }
        let before = Set(all().map(\.number))
        let mc = try await openMissionControl()
        let number = (display.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        guard let add = subgroup(mc, number: number, identifier: "mc.spaces.add"),
              AXUIElementPerformAction(add, kAXPressAction as CFString) == .success else { throw DesktopError.creationFailed }
        for _ in 0..<25 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let new = all().first(where: { !before.contains($0.number) && $0.displayID == display.id }) {
                // Selecting it closes Mission Control and makes the destination explicit.
                try await activate(new)
                return new
            }
        }
        throw DesktopError.creationFailed
    }
    @MainActor static func activate(_ desktop: Desktop) async throws {
        guard all(includeFullScreen: true).contains(where: { $0.number == desktop.number }) else { throw DesktopError.missingDesktop }
        if all(includeFullScreen: true).first(where: { $0.displayID == desktop.displayID && $0.isCurrent })?.number == desktop.number && missionControl() == nil { return }
        let mc = try await openMissionControl()
        // The new Space appears in WindowServer before its Mission Control button.
        try await Task.sleep(nanoseconds: 500_000_000)
        guard let list = subgroup(mc, number: desktop.displayNumber, identifier: "mc.spaces.list") else { throw DesktopError.missionControl }
        // Re-read the index: Mission Control can reorder Spaces as they are used.
        guard let refreshed = all(includeFullScreen: true).first(where: { $0.number == desktop.number }) else { throw DesktopError.missingDesktop }
        let buttons = children(list)
        guard buttons.indices.contains(refreshed.index - 1),
              AXUIElementPerformAction(buttons[refreshed.index - 1], kAXPressAction as CFString) == .success else { throw DesktopError.switchFailed }
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if all(includeFullScreen: true).first(where: { $0.displayID == desktop.displayID && $0.isCurrent })?.number == desktop.number && missionControl() == nil { return }
        }
        throw DesktopError.switchFailed
    }

    @MainActor static func move(_ windows: [ManagedWindow], to desktop: Desktop) async throws {
        let numbers = windows.compactMap(\.number)
        guard numbers.count == windows.count else { throw DesktopError.moveFailed }
        let needingMove = numbers.filter { !spaces(for: $0).contains(desktop.number) }
        if needingMove.isEmpty { return }
        guard canMove, QuiltMoveToSpace(needingMove.map { NSNumber(value: $0) } as CFArray, desktop.number) else { throw DesktopError.unavailable }
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if numbers.allSatisfy({ spaces(for: $0).contains(desktop.number) }) { return }
        }
        throw DesktopError.moveFailed
    }
}
