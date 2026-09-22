import AppKit
import ApplicationServices
import TilezCore

struct ManagedWindow: Identifiable {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    let frame: CGRect
    var availability = WindowAvailability()
    var serverNumber: UInt32?
    var number: UInt32? { serverNumber ?? Desktops.windowNumber(element) }
    var stateLabel: String {
        [!availability.accessible ? "Other desktop" : nil, availability.fullScreen ? "Full screen" : nil,
         availability.minimized ? "Minimized" : nil, availability.hidden ? "Hidden" : nil,
         !availability.resizable && !availability.fullScreen && availability.accessible ? "Fixed size" : nil].compactMap { $0 }.joined(separator: " · ")
    }
    var id: String { number.map { "\(pid):window-\($0)" } ?? "\(pid):ax-\(CFHash(element))" }
}

struct Display: Identifiable {
    let id: String
    let name: String
    let bounds: CGRect
    let screen: NSScreen

    static var all: [Display] {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value).takeRetainedValue()
            let id = CFUUIDCreateString(nil, uuid)! as String
            let f = screen.visibleFrame
            return Display(id: id, name: screen.localizedName,
                           bounds: CGRect(x: f.minX, y: height - f.maxY, width: f.width, height: f.height), screen: screen)
        }
    }
    static func containing(_ rect: CGRect) -> Display? {
        all.max { a, b in
            let aa = a.bounds.intersection(rect), bb = b.bounds.intersection(rect)
            return (aa.isNull ? 0 : aa.width * aa.height) < (bb.isNull ? 0 : bb.width * bb.height)
        }
    }
    static var topology: String {
        all.map { "\($0.id):\(Int($0.bounds.minX)),\(Int($0.bounds.minY)),\(Int($0.bounds.width)),\(Int($0.bounds.height))" }.sorted().joined(separator: "|")
    }
    static func cocoa(_ ax: CGRect) -> CGRect {
        CGRect(x: ax.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - ax.maxY, width: ax.width, height: ax.height)
    }
    static var pointer: CGPoint {
        CGPoint(x: NSEvent.mouseLocation.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - NSEvent.mouseLocation.y)
    }
}

enum Accessibility {
    // AX is synchronous IPC. Keep grid operations off the event loop and serialize
    // them so a slow app cannot stall typing, dragging, or the Escape shortcut.
    private static let workQueue = DispatchQueue(label: "com.local.tilez.accessibility", qos: .userInitiated)
    private static let inventoryLock = NSLock()

    static func perform<T>(_ operation: @escaping () -> T) async throws -> T {
        try Task.checkCancellation()
        let result = await withCheckedContinuation { continuation in
            workQueue.async { continuation.resume(returning: operation()) }
        }
        try Task.checkCancellation()
        return result
    }

    struct Snapshot {
        let windows: [ManagedWindow]
        let respondingPIDs: Set<pid_t>
    }

    @MainActor static func windows(for pids: Set<pid_t>) async throws -> [ManagedWindow] {
        try await snapshot(for: pids).windows
    }

    @MainActor static func snapshot(for pids: Set<pid_t>) async throws -> Snapshot {
        // Capture AppKit display/application state on the main thread. Only AX and
        // WindowServer queries run on the worker, and only for the requested apps.
        let running = NSWorkspace.shared.runningApplications.filter {
            pids.contains($0.processIdentifier) && $0.activationPolicy == .regular && $0.processIdentifier != getpid()
        }
        let fullScreenSpaces = Set(Desktops.all(includeFullScreen: true).filter(\.isFullScreen).map(\.number))
        return try await perform {
            var responding: Set<pid_t> = []
            let windows = scanWindows(running: running, fullScreenSpaces: fullScreenSpaces, scope: pids,
                                      onResponse: { responding.insert($0) })
            return Snapshot(windows: windows, respondingPIDs: responding)
        }
    }

    private static var confirmedClosedNumbers: [String: String] = UserDefaults.standard.dictionary(forKey: "confirmedClosedWindows") as? [String: String] ?? [:]
    private static func closeSession(_ app: NSRunningApplication) -> String? {
        app.launchDate.map { "\(app.processIdentifier)|\($0.timeIntervalSince1970)" }
    }
    static func markClosed(_ window: ManagedWindow) {
        inventoryLock.lock()
        defer { inventoryLock.unlock() }
        guard let number = window.number, let app = NSRunningApplication(processIdentifier: window.pid), let session = closeSession(app) else { return }
        confirmedClosedNumbers[String(number)] = session
        UserDefaults.standard.set(confirmedClosedNumbers, forKey: "confirmedClosedWindows")
    }
    private static var retainedWindows: [UInt32: ManagedWindow] = [:]
    private static var enabledAccessibility: Set<pid_t> = []
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func rect(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute),
              let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func windows() -> [ManagedWindow] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
        let fullScreenSpaces = Set(Desktops.all(includeFullScreen: true).filter(\.isFullScreen).map(\.number))
        return scanWindows(running: running, fullScreenSpaces: fullScreenSpaces, scope: nil)
    }

    private static func scanWindows(running: [NSRunningApplication], fullScreenSpaces: Set<UInt64>, scope: Set<pid_t>?, onResponse: (pid_t) -> Void = { _ in }) -> [ManagedWindow] {
        inventoryLock.lock()
        defer { inventoryLock.unlock() }
        guard trusted else { return [] }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.15)
        var result: [ManagedWindow] = []
        var excludedNumbers: Set<UInt32> = []
        let records = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let runningByPID = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
        if scope == nil { enabledAccessibility.formIntersection(Set(runningByPID.keys)) }
        for app in running {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // An unresponsive app must not stall the entire menu for seconds.
            AXUIElementSetMessagingTimeout(element, 0.12)
            if !enabledAccessibility.contains(app.processIdentifier),
               let url = app.bundleURL,
               FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) {
                _ = AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                enabledAccessibility.insert(app.processIdentifier)
            }
            let raw = value(element, kAXWindowsAttribute) as? [AXUIElement]
            guard let windows = raw else { continue }
            onResponse(app.processIdentifier)
            for window in windows {
                AXUIElementSetMessagingTimeout(window, 0.12)
                let minimized = value(window, kAXMinimizedAttribute) as? Bool == true
                let isDocument = (value(window, kAXSubroleAttribute) as? String).map { $0 == kAXStandardWindowSubrole }
                if WindowInventory.shouldExclude(isDocument: isDocument, modal: value(window, kAXModalAttribute) as? Bool, minimized: minimized) {
                    if let number = Desktops.windowNumber(window) { excludedNumbers.insert(number) }
                    continue
                }
                guard let frame = rect(window), frame.width > 30, frame.height > 30 else { continue }
                var resizable = DarwinBoolean(false)
                let canResize = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &resizable) == .success && resizable.boolValue
                let availability = WindowAvailability(hidden: app.isHidden,
                    minimized: minimized,
                    fullScreen: value(window, "AXFullScreen") as? Bool == true, resizable: canResize,
                    document: value(window, kAXRoleAttribute) as? String == kAXWindowRole
                        && (minimized || isDocument == true)
                        && value(window, kAXModalAttribute) as? Bool != true)
                guard availability.listed else { continue }
                result.append(ManagedWindow(element: window, pid: app.processIdentifier, bundleID: app.bundleIdentifier ?? "\(app.processIdentifier)",
                    appName: app.localizedName ?? "App", title: value(window, kAXTitleAttribute) as? String ?? "", frame: frame, availability: availability, serverNumber: Desktops.windowNumber(window)))
            }
        }
        // AXWindows may contain only the current Space. Retain known elements and
        // use WindowServer's geometry/IDs to list other desktops without screenshots.
        for window in result { if let number = window.number { retainedWindows[number] = window } }
        let discovered = Set(result.compactMap(\.number))
        var otherDesktops: [ManagedWindow] = []
        var existing: Set<UInt32> = []
        var existingSessions: [String: String] = [:]
        for record in records {
            guard let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = runningByPID[pid],
                  (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = record[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            existing.insert(number)
            if let session = closeSession(app) { existingSessions[String(number)] = session }
            if discovered.contains(number) || excludedNumbers.contains(number) { continue }
            let spaces = Desktops.spaces(for: number)
            guard !spaces.isEmpty, frame.width > 100, frame.height > 80 else { continue }
            let old = retainedWindows[number].flatMap { $0.pid == pid ? $0 : nil }
            let fullScreen = !spaces.isDisjoint(with: fullScreenSpaces)
            let state = WindowAvailability(hidden: app.isHidden,
                minimized: old.map { value($0.element, kAXMinimizedAttribute) as? Bool == true } ?? false,
                fullScreen: fullScreen, resizable: old?.availability.resizable ?? false,
                accessible: false)
            let candidate = ManagedWindow(element: old?.element ?? AXUIElementCreateApplication(pid), pid: pid,
                bundleID: app.bundleIdentifier ?? "\(pid)", appName: app.localizedName ?? "App",
                title: old?.title ?? (record[kCGWindowName as String] as? String) ?? "\(app.localizedName ?? "App") window",
                frame: frame, availability: state, serverNumber: number)
            otherDesktops.append(candidate)
        }
        let confirmed = confirmedClosedNumbers.filter { number, session in
            // A scoped scan must not evict state belonging to a different app.
            if let scope, let owner = session.split(separator: "|").first.flatMap({ Int32($0) }), !scope.contains(owner) { return true }
            return existingSessions[number] == session && !discovered.contains(UInt32(number) ?? 0)
        }
        if confirmed != confirmedClosedNumbers {
            confirmedClosedNumbers = confirmed
            UserDefaults.standard.set(confirmed, forKey: "confirmedClosedWindows")
        }
        retainedWindows = retainedWindows.filter { number, window in
            if let scope, !scope.contains(window.pid) { return true }
            return existing.contains(number)
        }
        return WindowInventory.merge(accessible: result, otherDesktops: otherDesktops.filter { confirmedClosedNumbers[String($0.number ?? 0)] == nil })
    }

    enum NewWindowError: LocalizedError {
        case appClosed, unavailable(String), failed, transition(String)
        var errorDescription: String? {
            switch self {
            case .appClosed: return "The selected app is no longer running."
            case .unavailable(let name): return "\(name) has no enabled New Window command. Tilez can reopen and arrange its existing window, but cannot create extra independent windows."
            case .failed: return "The app did not accept its New Window command."
            case .transition(let name): return "\(name) did not finish leaving full screen or restoring its window. No grid was applied; try again after its animation or dialog finishes."
            }
        }
    }

    static func menuItem(pid: pid_t, labels: [String]) -> AXUIElement? {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let bar = value(element, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        var remaining = 500
        func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 7, remaining > 0 else { return nil }
            remaining -= 1
            let title = (value(element, kAXTitleAttribute) as? String ?? "")
                .replacingOccurrences(of: "…", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value(element, kAXRoleAttribute) as? String == kAXMenuItemRole,
               labels.contains(title), value(element, kAXEnabledAttribute) as? Bool != false { return element }
            for child in value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let match = find(child, depth: depth + 1) { return match }
            }
            return nil
        }
        return find(bar as! AXUIElement, depth: 0)
    }

    static func newWindowCommand(pid: pid_t) -> AXUIElement? {
        // A New Chat/Conversation command can replace the current chat instead of opening a window.
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = value(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        return WindowMenuCommand.find(in: bar as! AXUIElement,
            title: { value($0, kAXTitleAttribute) as? String ?? "" },
            isItem: { value($0, kAXRoleAttribute) as? String == kAXMenuItemRole },
            isEnabled: { value($0, kAXEnabledAttribute) as? Bool != false },
            children: { value($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] },
            isDefault: {
                (value($0, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "n"
                    && (value($0, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue == 0
            })
    }

    @MainActor static func reopen(_ app: NSRunningApplication) async throws {
        guard let url = app.bundleURL else { throw NewWindowError.appClosed }
        app.unhide()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        // Activity Monitor has an explicit command that restores its main window.
        if app.bundleIdentifier == "com.apple.ActivityMonitor",
           let item = menuItem(pid: app.processIdentifier, labels: ["activity monitor"]) {
            _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        }
    }

    static func requestNewWindow(pid: pid_t) throws {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { throw NewWindowError.appClosed }
        app.unhide(); app.activate()
        guard let item = newWindowCommand(pid: pid) else { throw NewWindowError.unavailable(app.localizedName ?? "This app") }
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { throw NewWindowError.failed }
    }

    /// Wait for the native state transition before reading sizes or moving between Spaces.
    @MainActor static func prepareForTiling(_ window: ManagedWindow, preserveFullScreen: Bool) async throws -> Bool {
        if window.availability.fullScreen && preserveFullScreen { return false }
        var window = window
        if !window.availability.accessible || window.availability.fullScreen {
            if let number = window.number,
               let space = Desktops.all(includeFullScreen: true).first(where: { Desktops.spaces(for: number).contains($0.number) }) {
                try await Desktops.activate(space)
            }
            NSRunningApplication(processIdentifier: window.pid)?.unhide()
            NSRunningApplication(processIdentifier: window.pid)?.activate()
            let wantedID = window.id
            var found: ManagedWindow?
            for _ in 0..<30 {
                if let live = try await windows(for: [window.pid]).first(where: { $0.id == wantedID && $0.availability.accessible }) { found = live; break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let live = found else { throw NewWindowError.transition(window.appName) }
            window = live
        }
        let fullScreen = value(window.element, "AXFullScreen") as? Bool == true
        if fullScreen && preserveFullScreen { return false }
        NSRunningApplication(processIdentifier: window.pid)?.unhide()
        var changed = false
        if value(window.element, kAXMinimizedAttribute) as? Bool == true {
            guard AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else {
                throw NewWindowError.transition(window.appName)
            }
            changed = true
        }
        if fullScreen {
            guard AXUIElementSetAttributeValue(window.element, "AXFullScreen" as CFString, kCFBooleanFalse) == .success else {
                throw NewWindowError.transition(window.appName)
            }
            changed = true
        }
        if changed {
            var stable = 0
            var previous: CGRect?
            for _ in 0..<50 {
                try await Task.sleep(nanoseconds: 200_000_000)
                try Task.checkCancellation()
                let frame = rect(window.element)
                let settled = value(window.element, "AXFullScreen") as? Bool != true
                    && value(window.element, kAXMinimizedAttribute) as? Bool != true
                let onDesktop = Desktops.windowNumber(window.element).map { number in
                    !Desktops.spaces(for: number).isDisjoint(with: Set(Desktops.all().map(\.number)))
                } ?? false
                if settled && onDesktop, let frame, let previous, Geometry.approximatelyEqual(frame, previous) { stable += 1 }
                else { stable = 0 }
                previous = frame
                if stable >= 4 { return true }
            }
            throw NewWindowError.transition(window.appName)
        }
        return true
    }

    static func focused(in windows: [ManagedWindow], fallbackPID: pid_t?) -> ManagedWindow? {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pid = front == getpid() ? fallbackPID : front
        guard let pid else { return nil }
        let app = AXUIElementCreateApplication(pid)
        if let value = value(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
            if let exact = windows.first(where: { CFEqual($0.element, value) }) { return exact }
        }
        return windows.first { $0.pid == pid }
    }

    static func window(at point: CGPoint, in windows: [ManagedWindow]) -> ManagedWindow? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        let window = value(hit, kAXWindowAttribute) ?? hit
        return windows.first { CFEqual($0.element, window) }
    }

    static func isTitleBar(at point: CGPoint, window: ManagedWindow) -> Bool {
        guard window.frame.contains(point), point.y < window.frame.minY + 38 else { return false }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }
        let role = value(hit, kAXRoleAttribute) as? String ?? ""
        return ![kAXButtonRole, kAXTextFieldRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXCheckBoxRole].contains(role)
    }

    @discardableResult
    static func move(_ window: ManagedWindow, to target: CGRect) -> Bool {
        guard window.availability.accessible, value(window.element, "AXFullScreen") as? Bool != true,
              value(window.element, kAXMinimizedAttribute) as? Bool != true else { return false }
        var origin = CGPoint(x: target.minX.rounded(), y: target.minY.rounded())
        var size = CGSize(width: target.width.rounded(), height: target.height.rounded())
        guard let positionValue = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        // Resize again after moving because apps can constrain size to the old display.
        _ = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, positionValue)
        let resized = AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        return moved == .success && resized == .success
    }
}
