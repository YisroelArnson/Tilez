import AppKit
import Combine
import QuiltCore

struct GridAppChoice: Identifiable {
    let app: GridApp
    let url: URL
    var id: String { app.bundleID }
}

@MainActor final class GridEditorModel: ObservableObject {
    @Published var grid = DesktopGrid()
    @Published var selectedCell: Int?
    @Published var choosingApp = false
    @Published var search = ""
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
    private(set) var display: Display?
    private(set) var desktop: Desktop?
    private var locationKey = ""
    private var sessions: [String: DesktopGrid]
    private var task: Task<Void, Never>?
    private var undoDrafts: [DesktopGrid] = []
    private let defaults: UserDefaults
    let manager: WindowManager
    private var icons: [String: NSImage] = [:]

    init(manager: WindowManager, defaults: UserDefaults = .standard) {
        self.manager = manager; self.defaults = defaults
        sessions = defaults.data(forKey: "desktopGridsV2")
            .flatMap { try? JSONDecoder().decode([String: DesktopGrid].self, from: $0) }?
            .filter { $0.value.isValid } ?? [:]
        saved = defaults.data(forKey: "savedGridsV2")
            .flatMap { try? JSONDecoder().decode([SavedGrid].self, from: $0) }?
            .filter { $0.grid.isValid } ?? []
    }

    func begin(on display: Display) {
        self.display = display
        desktop = Desktops.current(displayID: display.id)
        locationKey = desktop?.id ?? display.id
        grid = sessions[locationKey] ?? DesktopGrid()
        selectedCell = nil; choosingApp = false; showingSaved = false; saving = false
        search = ""; message = ""; isError = false; undoDrafts = []
        trusted = Accessibility.trusted
        if desktop == nil { message = "Open a regular desktop to arrange a grid here."; isError = true }
        loadApps()
    }

    func persist() {
        guard !locationKey.isEmpty else { return }
        sessions[locationKey] = grid
        defaults.set(try? JSONEncoder().encode(sessions), forKey: "desktopGridsV2")
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
        choosingApp = false; selectedCell = nil
        edit { $0.resize(columns: columns, rows: rows) }
    }
    func choose(_ index: Int) {
        guard !busy, grid.slots.indices.contains(index) else { return }
        selectedCell = index; search = ""; choosingApp = true
        showingSaved = false; saving = false
    }
    func addApp() {
        guard !busy else { return }
        var target: Int?
        edit { target = $0.makeRoom() }
        if let target { choose(target) }
        else { message = "This grid is full. Choose a cell to replace its app." }
    }
    func assign(_ app: GridApp) {
        guard let index = selectedCell, grid.slots.indices.contains(index) else { return }
        edit { $0.slots[index] = GridSlot(app: app) }
        choosingApp = false; search = ""
    }
    func clear(_ index: Int) {
        guard grid.slots.indices.contains(index) else { return }
        edit { $0.slots[index] = GridSlot() }
        choosingApp = false
    }
    func move(from: Int, to: Int, repeating: Bool) {
        edit { $0.move(from: from, to: to, repeating: repeating) }
        selectedCell = to; choosingApp = false
    }
    func undo() {
        guard !busy, let previous = undoDrafts.popLast() else { return }
        grid = previous; choosingApp = false; selectedCell = nil; persist()
    }
    func newGrid() {
        guard !busy else { return }
        edit { $0 = DesktopGrid() }
        selectedCell = nil; choosingApp = false; showingSaved = false
    }
    func save() {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, grid.filledCount > 0 else { return }
        saved.append(SavedGrid(name: name, grid: grid))
        defaults.set(try? JSONEncoder().encode(saved), forKey: "savedGridsV2")
        saving = false; message = "Saved “\(name)”"
    }
    func load(_ item: SavedGrid) {
        edit { $0 = item.grid.template }
        showingSaved = false; selectedCell = nil; choosingApp = false
    }
    func deleteSaved(_ id: UUID) {
        saved.removeAll { $0.id == id }
        defaults.set(try? JSONEncoder().encode(saved), forKey: "savedGridsV2")
    }
    func dismissLayer() {
        if busy { task?.cancel(); return }
        if choosingApp { choosingApp = false }
        else if saving { saving = false }
        else if showingSaved { showingSaved = false }
        else { persist(); onDismiss?() }
    }
    func cancel() { task?.cancel() }
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
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        var urls = running.compactMap(\.bundleURL)
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
        apps = urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, seen.insert(id).inserted,
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

    func openGrid() {
        guard !busy, grid.filledCount > 0, let display, let desktop else { return }
        trusted = Accessibility.trusted
        guard trusted else { Accessibility.requestPermission(); return }
        choosingApp = false; saving = false; showingSaved = false
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
                    manager: self.manager, progress: { self.message = $0 },
                    prepared: { index, binding in
                        // Persist successful creation even if a later app cannot open a window.
                        self.grid.slots[index].binding = binding; self.persist()
                    })
                self.grid = result.grid; self.persist()
                if result.exact {
                    self.message = ""; self.onFinished?()
                } else {
                    self.message = result.message; self.isError = true
                }
            } catch is CancellationError {
                self.message = "Stopped. Windows already opened stay available."
            } catch {
                self.message = error.localizedDescription; self.isError = true
                // Keep the error and editor on the requested desktop after an app opens elsewhere.
                try? await Desktops.activate(desktop)
            }
        }
    }
}
