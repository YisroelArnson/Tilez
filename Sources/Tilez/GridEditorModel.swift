import AppKit
import Combine
import TilezCore

struct GridAppChoice: Identifiable, Sendable {
    let app: GridApp
    let url: URL
    var id: String { app.bundleID }
}

@MainActor final class GridEditorModel: ObservableObject {
    @Published var grid = DesktopGrid.emptyDesktop
    @Published var selectedCell: Int?
    @Published var choosingApp = false
    @Published var search = "" { didSet { selectedAppID = nil } }
    @Published var selectedAppID: String?
    @Published var savedSearch = "" { didSet { selectedSavedID = nil } }
    @Published var selectedSavedID: UUID?
    @Published var resizing = false
    @Published var draftColumns = 2
    @Published var draftRows = 2
    @Published var apps: [GridAppChoice] = []
    @Published var saved: [SavedGrid] = []
    @Published var showingSaved = false
    @Published var saving = false
    @Published var saveName = ""
    @Published var message = ""
    @Published var isError = false
    @Published var busy = false
    var hasOpened: Bool { grid.slots.contains { $0.binding != nil } }
    @Published var trusted = Accessibility.trusted
    var onDismiss: (() -> Void)?
    var onFinished: (() -> Void)?
    var onFocusGrid: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    /// A newer version found by a background check, shown as a pill in the grid.
    @Published var availableUpdate: String?
    var hasActiveLayer: Bool { choosingApp || saving || showingSaved || resizing }
    enum SaveKind { case workspace, layout }
    @Published var saveKind = SaveKind.workspace
    @Published var saveAllScreens = false
    /// Shared with Quick Add and the workspace panel.
    var workspaces: WorkspaceStore?
    var onOpenWorkspace: ((Workspace) -> Void)?
    var onRenameWorkspace: ((Workspace) -> Void)?
    /// Called with the arranged grid after Apply places its windows.
    var onApplied: ((DesktopGrid) -> Void)?
    /// The workspace this screen is showing, which ⌘S saves.
    @Published private(set) var shownWorkspace: Workspace?
    private var loadedLayout = false
    private var selections: [String: Int] = [:]
    private(set) var display: Display?
    private(set) var desktop: Desktop?
    private var locationKey = ""
    private(set) var originalGrid = DesktopGrid.emptyDesktop
    private var discoveryTask: Task<Void, Never>?
    private var discoveryGeneration = UUID()
    private var dividerDraft: DesktopGrid?
    private var task: Task<Void, Never>?
    private var undoDrafts: [DesktopGrid] = []
    private let defaults: UserDefaults
    let manager: WindowManager
    private var icons: [String: NSImage] = [:]
    private var appLoadTask: Task<Void, Never>?
    private var appsLoadedAt: Date?
    @Published private(set) var loadingApps = false

    init(manager: WindowManager, defaults: UserDefaults = .standard) {
        self.manager = manager; self.defaults = defaults
        saved = defaults.data(forKey: "savedGridsV2")
            .flatMap { try? JSONDecoder().decode([SavedGrid].self, from: $0) }?
            .filter { $0.grid.isValid } ?? []
    }

    func begin(on display: Display, snapshot: DesktopGrid? = nil) {
        discoveryTask?.cancel()
        let generation = UUID()
        discoveryGeneration = generation
        self.display = display
        desktop = Desktops.current(displayID: display.id, includeFullScreen: true)
        locationKey = desktop?.id ?? display.id
        let captured = snapshot ?? desktop.map { Self.captureDesktop(display: display, desktop: $0, manager: manager) } ?? .emptyDesktop
        let capturedFrames = captured.frames(in: display.bounds)
        grid = snapshot ?? DesktopGrid.visibleDesktop(panes: Array(zip(captured.slots, capturedFrames)), in: display.bounds)
        originalGrid = grid
        selectedCell = selections[locationKey].flatMap { grid.slots.indices.contains($0) ? $0 : nil } ?? 0
        closeLayers()
        search = ""; message = ""; isError = false; undoDrafts = []; dividerDraft = nil
        trusted = Accessibility.trusted
        if desktop == nil { message = "This desktop is unavailable."; isError = true }
        loadApps()
        loadedLayout = false
        updateWorkspaceStatus()
        guard snapshot == nil, trusted, let desktop, !captured.slots.allSatisfy({ $0.binding == nil }) else { return }
        let initial = grid
        discoveryTask = Task { [weak self] in
            do {
                let panes = try await Self.livePanes(captured, display: display)
                guard let self, self.discoveryGeneration == generation, !self.busy,
                      self.undoDrafts.isEmpty, self.grid == initial, !self.hasActiveLayer else { return }
                guard Desktops.current(displayID: display.id, includeFullScreen: true)?.number == desktop.number else { return }
                self.grid = DesktopGrid.visibleDesktop(panes: panes, in: display.bounds)
                self.originalGrid = self.grid
                self.selectedCell = min(self.selectedCell ?? 0, self.grid.slots.count - 1)
                self.updateWorkspaceStatus()
            } catch { /* Preview remains usable if discovery is cancelled or unavailable. */ }
        }
    }

    /// Ignore dialogs and panels when AX can identify them, and minimized or hidden windows. A
    /// temporarily unresponsive app keeps its WindowServer preview instead of disappearing.
    static func livePanes(_ captured: DesktopGrid, display: Display) async throws -> [(GridSlot, CGRect)] {
        let capturedFrames = captured.frames(in: display.bounds)
        let pids = Set(captured.slots.compactMap { $0.binding?.windowID.split(separator: ":").first.flatMap { Int32($0) } })
        guard !pids.isEmpty else { return [] }
        let response = try await Accessibility.snapshot(for: pids)
        let byID = Dictionary(uniqueKeysWithValues: response.windows.map { ($0.id, $0) })
        return captured.slots.enumerated().compactMap { index, slot -> (GridSlot, CGRect)? in
            guard let binding = slot.binding else { return nil }
            if let window = byID[binding.windowID] {
                guard window.availability.document, !window.availability.minimized, !window.availability.hidden else { return nil }
                var updated = slot; updated.title = window.title
                return (updated, window.availability.fullScreen ? display.bounds : window.frame)
            }
            let pid = binding.windowID.split(separator: ":").first.flatMap { Int32($0) }
            if let pid, response.respondingPIDs.contains(pid) { return nil }
            return (slot, capturedFrames[index])
        }
    }

    /// The windows a person can see on `desktop` within `display`, as the grid shows them.
    static func visibleDesktop(display: Display, desktop: Desktop, manager: WindowManager) async throws -> DesktopGrid {
        let captured = captureDesktop(display: display, desktop: desktop, manager: manager)
        guard Accessibility.trusted else { return captured }
        return DesktopGrid.visibleDesktop(panes: try await livePanes(captured, display: display), in: display.bounds)
    }

    /// Every normal window on `desktop` within `display`, front to back, bound to its live window.
    static func captureDesktop(display: Display, desktop: Desktop, manager: WindowManager) -> DesktopGrid {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isHidden && $0.processIdentifier != getpid()
        }
        let apps = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
        let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let panes = records.compactMap { record -> (GridSlot, CGRect)? in
            guard (record[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = apps[pid], let bundleID = app.bundleIdentifier,
                  let number = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let raw = record[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw), frame.width > 100, frame.height > 80,
                  Display.containing(frame)?.id == display.id,
                  Desktops.spaces(for: number).contains(desktop.number),
                  let session = manager.processSession(pid) else { return nil }
            let binding = GridWindowBinding(windowID: "\(pid):window-\(number)", processSession: session)
            return (GridSlot(app: GridApp(bundleID: bundleID, name: app.localizedName ?? "App"), binding: binding,
                             title: record[kCGWindowName as String] as? String), frame)
        }
        return DesktopGrid.desktop(panes: panes, in: display.bounds)
    }

    // Only explicit saved templates persist. A new invocation always reads the desktop.
    func persist() {
        guard !locationKey.isEmpty else { return }
        selections[locationKey] = selectedCell
    }

    func endEditing() {
        discoveryTask?.cancel()
        discoveryGeneration = UUID()
        dividerDraft = nil
        persist()
    }

    private func edit(_ change: (inout DesktopGrid) -> Void) {
        guard !busy else { return }
        let previous = grid
        change(&grid)
        if previous != grid {
            undoDrafts.append(previous)
            if undoDrafts.count > 40 { undoDrafts.removeFirst() }
            message = ""; isError = false
            persist()
        }
    }

    func resize(columns: Int, rows: Int) {
        guard !busy else { return }
        let column = (selectedCell ?? 0) % grid.columns
        let row = (selectedCell ?? 0) / grid.columns
        edit { $0.resize(columns: columns, rows: rows) }
        selectedCell = min(row, grid.rows - 1) * grid.columns + min(column, grid.columns - 1)
        closeLayers()
    }
    func select(_ index: Int) {
        guard grid.slots.indices.contains(index) else { return }
        closeLayers()
        selectedCell = index; persist()
    }
    func choose(_ index: Int) {
        guard !busy, grid.slots.indices.contains(index) else { return }
        closeLayers()
        selectedCell = index; search = ""; choosingApp = true
    }
    func addApp() {
        guard !busy else { return }
        var target: Int?
        edit { draft in
            if let empty = draft.slots.firstIndex(where: { $0.app == nil }) { target = empty }
            else {
                let index = selectedCell ?? 0
                let frame = draft.normalizedFrames[index]
                target = draft.split(index, toward: frame.width >= frame.height ? .right : .bottom)
            }
        }
        if let target { choose(target) }
        else { message = "This grid is full. Choose a cell to replace its app." }
    }
    func assign(_ app: GridApp) {
        guard !busy, let index = selectedCell, grid.slots.indices.contains(index) else { return }
        edit { draft in
            // Replacing a pane's app closes its window on Apply, the same as removing the pane.
            if let binding = draft.slots[index].binding, draft.windowsToClose?.contains(binding) != true {
                draft.windowsToClose = (draft.windowsToClose ?? []) + [binding]
            }
            draft.slots[index] = GridSlot(app: app, opensNewWindow: true)
        }
        closeLayers(); search = ""
    }
    func clear(_ index: Int) {
        guard !busy, grid.slots.indices.contains(index) else { return }
        edit { $0.slots[index] = GridSlot() }
        closeLayers()
    }
    func split(_ index: Int, toward edge: PaneEdge) {
        var added: Int?
        let gap = CGSize(width: 10 / (display?.bounds.width ?? 1250), height: 10 / (display?.bounds.height ?? 1250))
        edit { added = $0.split(index, toward: edge, gap: gap) }
        if let added { choose(added) }
    }
    func removePane(_ index: Int) {
        guard !busy, grid.slots.indices.contains(index) else { return }
        edit { draft in
            if let binding = draft.slots[index].binding {
                draft.windowsToClose = (draft.windowsToClose ?? []) + [binding]
            }
            let closing = draft.windowsToClose
            draft.removePane(index)
            draft.windowsToClose = closing
        }
        selectedCell = min(index, grid.slots.count - 1); closeLayers()
    }
    func removeAllPanes() {
        guard !busy else { return }
        edit { draft in
            var closing = draft.windowsToClose ?? []
            for binding in draft.slots.compactMap(\.binding) where !closing.contains(binding) {
                closing.append(binding)
            }
            draft = .emptyDesktop
            draft.windowsToClose = closing.isEmpty ? nil : closing
        }
        selectedCell = 0; closeLayers()
    }
    func previewDivider(_ divider: PaneDivider, position: CGFloat) {
        guard !busy else { return }
        if dividerDraft == nil { dividerDraft = grid; closeLayers() }
        guard var draft = dividerDraft else { return }
        draft.resizeDivider(divider, to: position)
        grid = draft
    }
    /// Dragging a pane's side or corner. Each update applies the whole offset to the grid as it
    /// was when the drag began; `finishDivider` then records one undo step.
    func previewResize(_ index: Int, edges: [PaneEdge], by offset: CGSize) {
        guard !busy else { return }
        if dividerDraft == nil { dividerDraft = grid; closeLayers() }
        guard var draft = dividerDraft, draft.slots.indices.contains(index) else { return }
        draft.resizePane(index, edges: edges, by: offset)
        grid = draft
    }
    func finishDivider() {
        guard let before = dividerDraft else { return }
        dividerDraft = nil
        if before != grid { undoDrafts.append(before); if undoDrafts.count > 40 { undoDrafts.removeFirst() } }
    }
    func resetDivider(_ divider: PaneDivider) {
        edit { $0.resetDivider(divider) }
        closeLayers()
    }
    /// Tidy panes that drifted out of line back onto shared edges, keeping the arrangement.
    func realign() {
        guard !busy else { return }
        closeLayers()
        let gap = CGSize(width: 10 / (display?.bounds.width ?? 1250), height: 10 / (display?.bounds.height ?? 1250))
        let before = grid
        var aligned = true
        edit { aligned = $0.realign(gap: gap) }
        if !aligned { message = "These panes are too far apart to line up." }
        else if grid == before { message = "Panes are already aligned." }
    }
    /// Merging closes absorbed windows on Apply, the same as removing their panes.
    func merge(_ index: Int, toward edge: PaneEdge) {
        guard !busy, grid.slots.indices.contains(index) else { return }
        guard !grid.mergeCandidates(index, toward: edge).isEmpty else {
            message = "Those panes don’t line up. Press ⌘R to realign, or drag a divider to match them."; isError = false
            return
        }
        var merged: Int?
        edit { draft in
            let before = draft.slots.compactMap(\.binding)
            merged = draft.merge(index, toward: edge)
            let kept = draft.slots.compactMap(\.binding)
            let closing = before.filter { !kept.contains($0) }
            if !closing.isEmpty { draft.windowsToClose = (draft.windowsToClose ?? []) + closing }
        }
        if let merged { selectedCell = merged }
        closeLayers()
    }
    func move(from: Int, to: Int, repeating: Bool) {
        guard !busy, grid.slots.indices.contains(from), grid.slots.indices.contains(to) else { return }
        edit { draft in
            // A repeat replaces the target's window, which closes on Apply like a removed pane.
            let replaced = repeating ? draft.slots[to].binding : nil
            draft.move(from: from, to: to, repeating: repeating)
            if let replaced { draft.windowsToClose = (draft.windowsToClose ?? []) + [replaced] }
        }
        selectedCell = to; closeLayers()
    }
    func undo() {
        guard !busy, let previous = undoDrafts.popLast() else { return }
        grid = previous
        selectedCell = min(selectedCell ?? 0, grid.slots.count - 1)
        closeLayers(); persist()
    }
    func newGrid() {
        guard !busy else { return }
        edit { $0 = .emptyDesktop }
        selectedCell = 0; closeLayers()
    }
    func save() {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !name.isEmpty else { return }
        if saveKind == .workspace {
            let allScreens = saveAllScreens
            closeLayers()
            commitWorkspace { store, display in try await store.saveNew(named: name, allScreens: allScreens, from: display) }
            return
        }
        guard grid.filledCount > 0 else { return }
        saved.append(SavedGrid(name: name, grid: grid))
        defaults.set(try? JSONEncoder().encode(saved), forKey: "savedGridsV2")
        closeLayers(); message = "Saved layout “\(name)”"
    }
    /// ⌘S: save the workspace this screen is showing, or name a new one when it shows none.
    func saveWorkspace() {
        guard !busy else { return }
        guard shownWorkspace != nil else { beginSave(.workspace); return }
        closeLayers()
        commitWorkspace { store, display in try await store.saveShown(on: display) }
    }
    /// A workspace keeps the windows on screen, so unapplied edits are applied first.
    private func commitWorkspace(_ save: @escaping (WorkspaceStore, Display) async throws -> Workspace) {
        guard let workspaces, let display else { return }
        let run = { [weak self] in
            guard let self else { return }
            self.busy = true; self.isError = false; self.message = "Saving workspace…"
            self.task = Task { @MainActor [weak self] in
                do {
                    let workspace = try await save(workspaces, display)
                    guard let self else { return }
                    self.busy = false; self.task = nil
                    self.begin(on: display)
                    self.message = "Saved workspace “\(workspace.name)”"
                } catch {
                    guard let self else { return }
                    self.busy = false; self.task = nil
                    self.message = error is CancellationError ? "Stopped." : error.localizedDescription
                    self.isError = !(error is CancellationError)
                }
            }
        }
        if grid != originalGrid { apply(then: run) } else { run() }
    }
    /// Unapplied grid edits or windows that moved since the workspace was saved.
    var workspaceModified: Bool {
        guard let shownWorkspace, let display else { return false }
        return grid != originalGrid || shownWorkspace.isModified(on: display.id, showing: originalGrid)
    }
    func updateWorkspaceStatus() {
        _ = workspaces?.current() // Drops closed windows before the strip draws them.
        shownWorkspace = display.flatMap { workspaces?.shownWorkspace(on: $0) }
    }
    func load(_ item: SavedGrid) {
        guard !busy else { return }
        edit { $0 = item.grid.template }
        selectedCell = grid.slots.firstIndex(where: { $0.app == nil }) ?? 0
        loadedLayout = true
        closeLayers()
    }
    func open(_ item: SavedItem) {
        switch item.kind {
        case .layout(let layout): load(layout)
        case .workspace(let workspace): openWorkspace(workspace)
        }
    }
    func openWorkspace(_ workspace: Workspace) {
        guard !busy else { return }
        closeLayers(); onOpenWorkspace?(workspace)
    }
    func renameWorkspace(_ workspace: Workspace) {
        guard !busy else { return }
        closeLayers(); onRenameWorkspace?(workspace)
    }
    func deleteSaved(_ id: UUID) {
        guard !busy else { return }
        if let workspaces, workspaces.workspaces.contains(where: { $0.id == id }) {
            objectWillChange.send()
            workspaces.remove(id)
            updateWorkspaceStatus()
            return
        }
        saved.removeAll { $0.id == id }
        defaults.set(try? JSONEncoder().encode(saved), forKey: "savedGridsV2")
    }
    func dismissLayer() {
        if busy { task?.cancel(); return }
        if hasActiveLayer { closeLayers() }
        else { persist(); onDismiss?() }
    }
    func closeLayers() {
        choosingApp = false; saving = false; showingSaved = false; resizing = false
    }
    func beginSave(_ kind: SaveKind) {
        guard !busy, kind == .workspace || grid.filledCount > 0 else { return }
        closeLayers()
        saveKind = kind; saveAllScreens = false
        saveName = kind == .layout ? "\(grid.columns) × \(grid.rows) grid" : workspaces?.suggestedName ?? "Workspace"
        saving = true
    }
    func beginSaved() {
        guard !busy else { return }
        closeLayers(); savedSearch = ""; showingSaved = true
    }
    func beginResize() {
        guard !busy else { return }
        closeLayers()
        draftColumns = grid.columns; draftRows = grid.rows; resizing = true
    }
    func confirmResize() { resize(columns: draftColumns, rows: draftRows) }
    func repeatInEmptyCells(_ index: Int) {
        guard !busy, grid.slots.indices.contains(index), let app = grid.slots[index].app else { return }
        edit { draft in
            for target in draft.slots.indices where draft.slots[target].app == nil {
                draft.slots[target] = GridSlot(app: app, opensNewWindow: true)
            }
        }
    }
    var selectedAppChoice: GridAppChoice? {
        filteredApps.first { $0.id == selectedAppID } ?? filteredApps.first
    }
    /// Workspaces, then saved layouts, in one searchable list.
    struct SavedItem: Identifiable {
        enum Kind { case workspace(Workspace), layout(SavedGrid) }
        let kind: Kind
        var id: UUID { switch kind { case .workspace(let w): return w.id; case .layout(let l): return l.id } }
        var name: String { switch kind { case .workspace(let w): return w.name; case .layout(let l): return l.name } }
        var isWorkspace: Bool { if case .workspace = kind { return true }; return false }
    }
    var hasSavedItems: Bool { !saved.isEmpty || workspaces?.workspaces.isEmpty == false }
    var filteredSaved: [SavedItem] {
        let query = savedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = (workspaces?.workspaces ?? []).map { SavedItem(kind: .workspace($0)) } + saved.map { SavedItem(kind: .layout($0)) }
        return query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    var selectedSavedItem: SavedItem? {
        filteredSaved.first { $0.id == selectedSavedID } ?? filteredSaved.first
    }
    func moveSearchSelection(_ delta: Int) {
        if choosingApp {
            let results = filteredApps
            guard !results.isEmpty else { return }
            let index = results.firstIndex { $0.id == selectedAppChoice?.id } ?? 0
            selectedAppID = results[max(0, min(results.count - 1, index + delta))].id
        } else if showingSaved {
            let results = filteredSaved
            guard !results.isEmpty else { return }
            let index = results.firstIndex { $0.id == selectedSavedItem?.id } ?? 0
            selectedSavedID = results[max(0, min(results.count - 1, index + delta))].id
        }
    }
    func confirmSearchSelection() {
        if choosingApp, let choice = selectedAppChoice { assign(choice.app) }
        else if showingSaved, let item = selectedSavedItem { open(item) }
    }
    func cancel() { task?.cancel(); discoveryTask?.cancel() }
    func icon(for app: GridApp) -> NSImage {
        if let icon = icons[app.bundleID] { return icon }
        let url = apps.first { $0.id == app.bundleID }?.url
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)
        let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: app.name)!
        icons[app.bundleID] = icon
        return icon
    }
    var filteredApps: [GridAppChoice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? apps : apps.filter {
            $0.app.name.localizedCaseInsensitiveContains(query) || $0.app.bundleID.localizedCaseInsensitiveContains(query)
        }
    }
    private func loadApps() {
        // Keep the last catalog usable while refreshing; opening the editor never waits on disk.
        guard appLoadTask == nil,
              appsLoadedAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let urls = running.compactMap(\.bundleURL)
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        let ownBundleID = Bundle.main.bundleIdentifier
        loadingApps = true
        appLoadTask = Task { [weak self] in
            let choices = await Task.detached(priority: .userInitiated) {
                Self.discoverApps(urls: urls, runningIDs: runningIDs, ownBundleID: ownBundleID)
            }.value
            guard let self else { return }
            self.apps = choices
            self.appsLoadedAt = Date()
            self.loadingApps = false
            self.appLoadTask = nil
        }
    }

    nonisolated private static func discoverApps(urls: [URL], runningIDs: Set<String>, ownBundleID: String?) -> [GridAppChoice] {
        var urls = urls
        // Walk only application directories; never descend into application bundles.
        for root in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"] {
            if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                 includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                while let url = enumerator.nextObject() as? URL {
                    if url.pathExtension == "app" { urls.append(url) }
                    if url.pathComponents.count > URL(fileURLWithPath: root).pathComponents.count + 3 { enumerator.skipDescendants() }
                }
            }
        }
        var seen = Set<String>()
        return urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != ownBundleID, seen.insert(id).inserted,
                  bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool != true,
                  bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true else { return nil }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return GridAppChoice(app: GridApp(bundleID: id, name: name), url: url)
        }.sorted {
            if runningIDs.contains($0.id) != runningIDs.contains($1.id) { return runningIDs.contains($0.id) }
            return $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
        }
    }

    func openGrid() { apply(then: nil) }

    /// `next` runs after the windows are placed, in place of closing the grid.
    private func apply(then next: (() -> Void)?) {
        guard !busy, grid.isValid, let display, let desktop,
              grid.filledCount > 0 || originalGrid.filledCount > 0 else { return }
        guard Desktops.current(displayID: display.id, includeFullScreen: true)?.number == desktop.number else {
            message = "The desktop changed. Reopen Tilez on the desktop you want."; isError = true; return
        }
        discoveryTask?.cancel()
        trusted = Accessibility.trusted
        guard trusted else { Accessibility.requestPermission(); return }
        closeLayers()
        busy = true; isError = false; message = "Preparing your grid…"
        let request = grid
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.busy = false; self.task = nil
                self.manager.suppressUntil = Date().addingTimeInterval(1)
            }
            do {
                let result = try await GridLauncher.open(request, display: display, desktop: desktop,
                    manager: self.manager, original: self.originalGrid,
                    destinationChanged: { display, desktop in
                        self.display = display; self.desktop = desktop; self.locationKey = desktop.id
                    }, progress: { self.message = $0 },
                    prepared: { index, binding in
                        // Persist successful creation even if a later app cannot open a window.
                        self.grid.slots[index].binding = binding; self.persist()
                    })
                self.grid = result.grid; self.persist()
                // A saved layout opened here replaces the workspace this screen was showing.
                if self.loadedLayout, let display = self.display { self.workspaces?.layoutOpened(on: display) }
                self.onApplied?(result.grid)
                if let next {
                    // After this task finishes, so `next` can start its own.
                    Task { @MainActor in next() }
                } else if result.exact {
                    self.message = ""; self.onFinished?()
                } else {
                    self.message = result.message; self.isError = true
                }
            } catch is CancellationError {
                self.message = "Stopped. Windows already opened stay available."
            } catch {
                self.message = error.localizedDescription; self.isError = true
                // Keep the error and editor on the requested desktop after an app opens elsewhere.
                if let destination = self.desktop { try? await Desktops.activate(destination) }
            }
        }
    }
}
