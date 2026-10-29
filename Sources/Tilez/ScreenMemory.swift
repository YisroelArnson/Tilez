import AppKit
import SwiftUI
import TilezCore

private final class PutBackPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Keeps each disconnected screen's desktops separate on a surviving screen, and remembers
/// where their windows belong when the screen reconnects.
@MainActor final class ScreenMemoryController: ObservableObject {
    enum Phase { case asking, working, done, failed }
    @Published private(set) var phase = Phase.asking
    @Published private(set) var title = ""
    @Published private(set) var detail = ""
    @Published private(set) var icons: [NSImage] = []
    /// The prompt's "Always put windows back" checkbox.
    @Published var always = false
    private let store: WorkspaceStore
    private let defaults: UserDefaults
    private var memory: ScreenMemory
    private var transition: ScreenTransition
    private var disconnectedToPreserve: Set<String> = []
    private var screenGeneration = UUID()
    /// Reconnected screens whose windows can still go back, until the time given. Nothing is
    /// recorded while any are waiting, so their windows keep belonging to them.
    private var pending: [String: Date] = [:]
    private var timer: Timer?
    private var settleWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var panel: PutBackPanel?
    private var task: Task<Void, Never>?
    private static let memoryKey = "screenMemoryV1"
    private var manager: WindowManager { store.manager }

    init(store: WorkspaceStore, defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
        memory = defaults.data(forKey: Self.memoryKey).flatMap { try? JSONDecoder().decode(ScreenMemory.self, from: $0) } ?? ScreenMemory()
        transition = ScreenTransition(connected: Set(Display.all.map(\.id)))
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }),
            // A screen can come or go while the Mac sleeps; record before, and look again after.
            (workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.willSleep() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didWake() }
            }),
        ]
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
        record()
    }

    /// The windows that were on `display` before it disconnected and are still on another
    /// screen, and where they are, for the grid's Put back pill.
    func displaced(on display: Display) -> (windows: [GridSlot], location: String)? {
        guard pending[display.id] != nil else { return nil }
        let away = away()
        guard let grid = away.entries.first(where: { $0.displayID == display.id })?.grid else { return nil }
        return (grid.slots, whereabouts(grid.slots, location: away.location))
    }

    // MARK: Recording

    /// Each screen's windows, while more than one screen is connected and none is waiting for
    /// its windows to come back. With one screen there's nowhere else for windows to be.
    private func record() {
        expire()
        guard transition.permitsRecording, pending.isEmpty, task == nil else { return }
        let displays = Display.all
        // WindowServer drops a screen, and moves its windows, before AppKit's list catches up.
        guard displays.count > 1, Set(displays.map(\.id)).isSubset(of: Self.activeDisplayIDs) else { return }
        let windows = Self.windows(on: displays, manager: manager)
        var next = memory
        next.keep { windows.open.contains($0) }
        // With three screens, disconnecting one still leaves a multi-screen setup. Its windows
        // must keep their original ownership rather than becoming the surviving screen's record.
        let absent = Set(next.screens.filter { !Set(displays.map(\.id)).contains($0.key) }
            .flatMap { $0.value.compactMap { $0.slot.binding } })
        for display in displays {
            let panes = (windows.screens[display.id] ?? []).filter { !($0.0.binding.map(absent.contains) ?? false) }
            next.record(DesktopGrid.desktop(panes: panes, in: display.bounds), on: display.id, desktops: windows.desktops)
        }
        guard next != memory else { return }
        memory = next
        defaults.set(try? JSONEncoder().encode(memory), forKey: Self.memoryKey)
    }

    private static var activeDisplayIDs: Set<String> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Set(displays.prefix(Int(count)).compactMap { display in
            CGDisplayCreateUUIDFromDisplayID(display).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
        })
    }

    /// Every window of a regular app outside full screen, front to back, by the screen that
    /// holds most of it; which screen each can be moved back from, with its desktop and frame
    /// there; and every open window.
    private static func windows(on displays: [Display], manager: WindowManager)
        -> (screens: [String: [(GridSlot, CGRect)]], location: [GridWindowBinding: String], open: Set<GridWindowBinding>,
            desktops: [GridWindowBinding: String], whereabouts: [GridWindowBinding: ScreenMemory.Whereabouts]) {
        let apps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .map { ($0.processIdentifier, $0) })
        let desktops = Desktops.all(includeFullScreen: true)
        let fullScreen = Set(desktops.filter(\.isFullScreen).map(\.number))
        let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        func overlap(_ display: Display, _ frame: CGRect) -> CGFloat {
            let shared = display.bounds.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        var sessions: [pid_t: String] = [:]
        var screens: [String: [(GridSlot, CGRect)]] = [:]
        var location: [GridWindowBinding: String] = [:]
        var open: Set<GridWindowBinding> = []
        var membership: [GridWindowBinding: String] = [:]
        var whereabouts: [GridWindowBinding: ScreenMemory.Whereabouts] = [:]
        for record in records {
            guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = apps[pid], let bundleID = app.bundleIdentifier,
                  let number = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let raw = record[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw), frame.width > 100, frame.height > 80,
                  let session = sessions[pid] ?? manager.processSession(pid) else { continue }
            sessions[pid] = session
            // WindowServer keeps a closed window's number only while the app holds it off every desktop.
            let spaces = Desktops.spaces(for: number)
            guard !spaces.isEmpty else { continue }
            let binding = GridWindowBinding(windowID: "\(pid):window-\(number)", processSession: session)
            open.insert(binding)
            guard spaces.isDisjoint(with: fullScreen), (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { continue }
            let desktop = spaces.count == 1 ? desktops.first(where: { spaces.contains($0.number) }) : nil
            guard let display = displays.max(by: { overlap($0, frame) < overlap($1, frame) }), overlap(display, frame) > 0 else { continue }
            screens[display.id, default: []].append((GridSlot(app: GridApp(bundleID: bundleID, name: app.localizedName ?? "App"), binding: binding), frame))
            if let desktop {
                membership[binding] = desktop.spaceIdentity
            }
            // A hidden app's windows stay hidden rather than coming back.
            guard !app.isHidden else { continue }
            location[binding] = display.id
            let clipped = display.bounds.intersection(frame)
            whereabouts[binding] = ScreenMemory.Whereabouts(displayID: display.id, desktop: desktop?.spaceIdentity,
                frame: CGRect(x: (clipped.minX - display.bounds.minX) / display.bounds.width, y: (clipped.minY - display.bounds.minY) / display.bounds.height,
                              width: clipped.width / display.bounds.width, height: clipped.height / display.bounds.height))
        }
        return (screens, location, open, membership, whereabouts)
    }

    // MARK: Screens coming back

    private func willSleep() {
        record()
        screenGeneration = UUID()
        settleWork?.cancel(); settleWork = nil
        task?.cancel()
        hide()
        transition.sleep(remembered: Set(memory.screens.keys))
    }

    private func didWake() {
        transition.wake()
        screensChanged()
    }

    private func screensChanged() {
        transition.screensChanged()
        screenGeneration = UUID()
        task?.cancel()
        settleWork?.cancel()
        let generation = screenGeneration
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.screenGeneration == generation else { return }
                self.screensSettled()
            }
        }
        settleWork = work
        // macOS keeps moving windows for a few seconds after a screen comes or goes, sometimes
        // back where they were; only what's still away afterwards needs putting back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func screensSettled() {
        let now = Set(Display.all.map(\.id))
        guard let change = transition.settle(on: now) else { return }
        disconnectedToPreserve.formUnion(change.removed)
        disconnectedToPreserve.subtract(now)
        for id in pending.keys where !now.contains(id) { pending[id] = nil }
        for id in change.recover where memory.screens[id] != nil { pending[id] = Date().addingTimeInterval(15 * 60) }
        handleScreenChanges()
    }

    private func handleScreenChanges() {
        guard transition.permitsRecording, task == nil else { return }
        if !disconnectedToPreserve.isEmpty {
            keepDesktopsSeparate(from: disconnectedToPreserve)
        }
        if task == nil && !pending.isEmpty { offer() }
    }

    // MARK: Screens going away

    private func keepDesktopsSeparate(from removed: Set<String>) {
        // Requeue only cancellation, so a late screen/resolution notification can resume work
        // after settling without repeatedly retrying a real failure such as the desktop limit.
        disconnectedToPreserve.subtract(removed)
        guard defaults.object(forKey: GridEditorModel.keepDesktopsKey) as? Bool ?? true,
              Accessibility.trusted, Desktops.canMove,
              let display = Display.all.first(where: {
                  let number = ($0.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
                  return CGDisplayIsBuiltin(number) != 0
              }) ?? Display.all.first else { return }
        // Ignore closed/restarted apps, hidden and minimized windows, native full screen, and
        // windows explicitly assigned to all desktops. AX eligibility is checked after refresh.
        let visible = Set(Self.windows(on: Display.all, manager: manager).location.keys)
        guard !memory.desktopGroups(on: removed, keeping: visible).isEmpty else { return }
        phase = .working; title = "Keeping desktops separate…"; detail = ""
        present(on: display.id)
        hideWork?.cancel()
        let generation = screenGeneration
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                self.handleScreenChanges()
            }
            do {
                let pids = Set(visible.compactMap { $0.windowID.split(separator: ":").first.flatMap { Int32($0) } })
                try await self.manager.refresh(for: pids)
                try Task.checkCancellation()
                let movable = self.movableBindings().intersection(visible)
                let groups = self.memory.desktopGroups(on: removed, keeping: movable)
                try await self.arrangeGroups(groups, on: { _ in display.id })
                try Task.checkCancellation()
                self.phase = .done; self.title = "Kept your desktops separate"; self.detail = ""
                self.scheduleHide(after: 2)
            } catch is CancellationError {
                if generation != self.screenGeneration {
                    self.disconnectedToPreserve.formUnion(removed.subtracting(Set(Display.all.map(\.id))))
                }
                self.hide()
            } catch {
                self.phase = .failed; self.title = "Some desktops couldn’t be kept separate"
                self.detail = error.localizedDescription; self.scheduleHide(after: 8)
            }
        }
    }

    private func movableBindings() -> Set<GridWindowBinding> {
        Set(manager.windows.compactMap { window in
            guard !window.availability.minimized, !window.availability.hidden, !window.availability.fullScreen,
                  window.availability.document, let number = window.number, Desktops.spaces(for: number).count == 1,
                  let session = manager.processSession(window.pid) else { return nil }
            return GridWindowBinding(windowID: window.id, processSession: session)
        })
    }

    /// Reuse an original Space if macOS preserved it; otherwise create one per group. The
    /// launcher gathers only these exact windows, fitting their original arrangement to the
    /// destination screen, and never opens windows or detaches an app's tabs.
    /// Putting back (`exact`) also rearranges a group whose windows are on its desktop but out of
    /// place, as when macOS returned them itself.
    private func arrangeGroups(_ groups: [ScreenMemory.DesktopGroup], on destination: (String) -> String, exact: Bool = false) async throws {
        let topology = Set(Display.all.map(\.id))
        let whereabouts = exact ? Self.windows(on: Display.all, manager: manager).whereabouts : [:]
        let originalDesktops = Desktops.all(includeFullScreen: true).filter(\.isCurrent)
        var changedDesktop = false
        var failure: Error?
        do {
            for group in groups {
                try Task.checkCancellation()
                guard Set(Display.all.map(\.id)) == topology,
                      let display = Display.all.first(where: { $0.id == destination(group.displayID) }) else { throw GridLaunchError.changedDesktop }
                let replacement = memory.replacement(for: group, on: display.id)
                let existing = Desktops.all().first { $0.displayID == display.id && $0.spaceIdentity == group.desktop }
                    ?? Desktops.all().first { $0.displayID == display.id && $0.spaceIdentity == replacement }
                let ids = Set(group.grid.slots.compactMap { $0.binding?.windowID })
                let frames = group.grid.normalizedFrames
                let inPlace = !exact || group.grid.slots.indices.allSatisfy { index in
                    guard let binding = group.grid.slots[index].binding, let now = whereabouts[binding]?.frame else { return true }
                    return ScreenMemory.isAt(now, frames[index])
                }
                if let existing, inPlace, manager.windows.filter({ ids.contains($0.id) }).allSatisfy({ window in
                    window.number.map { Desktops.spaces(for: $0).contains(existing.number) } == true
                }) { continue }
                let desktop: Desktop
                changedDesktop = true
                if let existing { desktop = existing; try await Desktops.activate(existing) }
                else { desktop = try await Desktops.create(on: display) }
                // Save before gathering: if an app stalls, retry into this same desktop.
                memory.rememberReplacement(desktop.spaceIdentity, for: group, on: display.id)
                defaults.set(try? JSONEncoder().encode(memory), forKey: Self.memoryKey)
                try Task.checkCancellation()
                guard Set(Display.all.map(\.id)) == topology else { throw GridLaunchError.changedDesktop }
                _ = try await GridLauncher.open(group.grid, display: display, desktop: desktop, manager: manager,
                    gathering: true, progress: { self.detail = $0 }, prepared: { _, _ in })
            }
        } catch { failure = error }
        // Do not strand the user on the last created desktop, including after partial failure.
        // A cancelled/topology-changing operation leaves desktop selection to the user/macOS.
        if changedDesktop && !Task.isCancelled && Set(Display.all.map(\.id)) == topology {
            for desktop in originalDesktops where Desktops.all(includeFullScreen: true).contains(where: { $0.number == desktop.number }) {
                try? await Desktops.activate(desktop)
            }
        }
        if let failure { throw failure }
    }

    private func expire() {
        let now = Date()
        pending = pending.filter { $0.value > now }
    }

    /// What can go back to each waiting screen, at its remembered frames, and where each window is now.
    private func away() -> (entries: [(displayID: String, grid: DesktopGrid)], location: [GridWindowBinding: String]) {
        expire()
        guard !pending.isEmpty else { return ([], [:]) }
        let windows = Self.windows(on: Display.all, manager: manager)
        let entries = pending.keys.sorted().compactMap { id in
            memory.displaced(from: id, whereabouts: { windows.whereabouts[$0] }).map { (displayID: id, grid: $0) }
        }
        return (entries, windows.location)
    }

    private func whereabouts(_ windows: [GridSlot], location: [GridWindowBinding: String]) -> String {
        let ids = Set(windows.compactMap { $0.binding.flatMap { location[$0] } })
        let names = Display.all.filter { ids.contains($0.id) }.map(\.name)
        return names.count == 1 ? names[0] : "other screens"
    }

    private func offer() {
        let away = away()
        // A screen whose windows are all back already, or closed, records again.
        for id in pending.keys where !away.entries.contains(where: { $0.displayID == id }) { pending[id] = nil }
        guard let first = away.entries.first else { return }
        if defaults.bool(forKey: GridEditorModel.putBackKey) { putBack(); return }
        let windows = away.entries.flatMap { $0.grid.slots }
        let names = away.entries.compactMap { entry in Display.all.first { $0.id == entry.displayID }?.name }
        title = "Put \(windows.count) window\(windows.count == 1 ? "" : "s") back on \(names.count == 1 ? names[0] : "\(names.count) screens")?"
        detail = "\(windows.count == 1 ? "It" : "They") moved to \(whereabouts(windows, location: away.location)) while "
            + (names.count == 1 ? "it was" : "those screens were") + " disconnected."
        icons = Self.icons(windows)
        always = false
        phase = .asking
        present(on: first.displayID)
        scheduleHide(after: 30)
    }

    /// Moves the windows waiting to go back to their remembered places: all of them, or only
    /// those for `displayIDs`. Minimized windows stay minimized.
    func putBack(on displayIDs: [String]? = nil) {
        guard transition.permitsRecording, task == nil else { return }
        if always { defaults.set(true, forKey: GridEditorModel.putBackKey); always = false }
        hideWork?.cancel()
        let entries = away().entries.filter { displayIDs?.contains($0.displayID) ?? true }
        guard let first = entries.first else { hide(); return }
        phase = .working; title = "Putting windows back…"; detail = ""
        present(on: first.displayID)
        guard Accessibility.trusted else {
            Accessibility.requestPermission()
            phase = .failed; title = "Tilez needs Accessibility access"
            detail = "Allow it in System Settings → Privacy & Security → Accessibility, then use Put back in the grid."
            scheduleHide(after: 8)
            return
        }
        let generation = screenGeneration
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.task = nil
                if generation != self.screenGeneration || !self.disconnectedToPreserve.isEmpty { self.handleScreenChanges() }
            }
            do {
                let pids = Set(entries.flatMap { $0.grid.slots.compactMap { $0.binding?.windowID.split(separator: ":").first.flatMap { Int32($0) } } })
                try await self.manager.refresh(for: pids)
                try Task.checkCancellation()
                let movable = Set(self.manager.windows.filter { !$0.availability.minimized && !$0.availability.hidden }.map(\.id))
                let groups = Desktops.canMove ? self.memory.desktopGroups(on: Set(entries.map(\.displayID)), keeping: self.movableBindings()) : []
                let grouped = Set(groups.flatMap { $0.grid.slots.compactMap { $0.binding?.windowID } })
                var count = grouped.count
                let destinations = entries.compactMap { entry -> (screen: WorkspaceScreen, displayID: String)? in
                    let frames = entry.grid.normalizedFrames
                    let kept = entry.grid.slots.indices.filter {
                        let id = entry.grid.slots[$0].binding?.windowID ?? ""
                        return movable.contains(id) && !grouped.contains(id)
                    }
                    count += kept.count
                    let grid = DesktopGrid(panes: kept.map { entry.grid.slots[$0] }, frames: kept.map { frames[$0] })
                    return WorkspaceScreen(displayID: entry.displayID, arranging: grid).map { ($0, entry.displayID) }
                }
                if !groups.isEmpty { try await self.arrangeGroups(groups, on: { $0 }, exact: true) }
                try Task.checkCancellation()
                if !destinations.isEmpty { try await self.store.arrange(destinations, progress: { self.detail = $0 }) }
                try Task.checkCancellation()
                // A screen whose windows didn't all make it back keeps waiting, so recording
                // doesn't make the screen they're on their home. The grid offers Put back.
                let location = Self.windows(on: Display.all, manager: self.manager).location
                for entry in entries where self.memory.displaced(from: entry.displayID, location: { location[$0] }) == nil {
                    self.pending[entry.displayID] = nil
                }
                self.phase = .done
                self.title = count == 0 ? "Those windows are already back" : "Put \(count) window\(count == 1 ? "" : "s") back"
                self.detail = ""
                self.scheduleHide(after: 1.6)
            } catch {
                if generation != self.screenGeneration { self.hide(); return }
                self.phase = .failed
                self.title = error is CancellationError ? "Stopped" : "Some windows couldn’t go back"
                self.detail = error is CancellationError ? "" : error.localizedDescription
                self.scheduleHide(after: 8)
            }
        }
    }

    /// Not now: the prompt goes away, and the grid offers Put back on that screen for a while.
    func dismiss() {
        if phase == .working { task?.cancel(); return }
        hide()
    }

    // MARK: Prompt

    private static func icons(_ windows: [GridSlot]) -> [NSImage] {
        var seen = Set<String>()
        return windows.compactMap(\.app).filter { seen.insert($0.bundleID).inserted }.prefix(4).compactMap { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        }
    }

    private func present(on displayID: String) {
        guard let display = Display.all.first(where: { $0.id == displayID }) ?? Display.all.first else { return }
        if panel == nil {
            // Non-activating, so the prompt never takes focus from what you're typing in.
            let panel = PutBackPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: PutBackView(controller: self))
            self.panel = panel
        }
        let size = CGSize(width: 580, height: 92)
        let screen = display.screen.visibleFrame
        panel?.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 16, width: size.width, height: size.height), display: true)
        panel?.orderFrontRegardless()
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { if self?.task == nil { self?.hide() } } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }
}

private struct PutBackView: View {
    @ObservedObject var controller: ScreenMemoryController

    var body: some View {
        HStack(spacing: 14) {
            leading.frame(minWidth: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(controller.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if !controller.detail.isEmpty {
                    Text(controller.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                if controller.phase == .asking {
                    Toggle("Always put windows back", isOn: $controller.always)
                        .toggleStyle(.checkbox).font(.system(size: 12))
                }
            }
            Spacer(minLength: 8)
            switch controller.phase {
            case .asking:
                Button("Not Now", action: controller.dismiss)
                Button("Put Back") { controller.putBack() }.buttonStyle(GridButtonStyle(primary: true))
            case .failed:
                Button("Close", action: controller.dismiss)
            case .working, .done:
                EmptyView()
            }
        }
        .buttonStyle(GridButtonStyle())
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The window draws the shadow; the surface only needs its glass.
        .glassSurface(RoundedRectangle(cornerRadius: 22), elevated: false)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var leading: some View {
        switch controller.phase {
        case .asking:
            HStack(spacing: -8) {
                ForEach(Array(controller.icons.enumerated()), id: \.offset) { _, icon in
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                }
            }.accessibilityHidden(true)
        case .working: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle").font(.system(size: 18))
        case .failed: Image(systemName: "exclamationmark.circle").font(.system(size: 18)).foregroundStyle(.red)
        }
    }
}
