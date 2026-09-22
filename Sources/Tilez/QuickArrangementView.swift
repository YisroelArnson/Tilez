import AppKit
import SwiftUI
import TilezCore


struct ArrangementGrid: View {
    @Binding var draft: WindowSetup
    private let columns = 5
    private let rows = 4

    private var resolvedGrid: (columns: Int, rows: Int) {
        let bounds = Display.all.first { $0.id == draft.displayID }?.bounds
            ?? Display.all.first { $0.screen == NSScreen.main }?.bounds
            ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let frames = TilezCore.Geometry.grid(count: draft.count, in: bounds, columns: draft.columns, rows: draft.rows, gap: draft.gap)
        return (Set(frames.map(\.minX)).count, Set(frames.map(\.minY)).count)
    }

    var body: some View {
        let grid = resolvedGrid
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                    ForEach(0..<(columns * rows), id: \.self) { index in
                        let column = index % columns + 1
                        let row = index / columns + 1
                        let selected = column <= grid.columns && row <= grid.rows
                            && (row - 1) * grid.columns + column <= draft.count
                        Button { select(column: column, row: row) } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? TilezStyle.accent.opacity(0.18) : Color.primary.opacity(0.035))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? TilezStyle.accent : Color.primary.opacity(0.14), lineWidth: selected ? 2 : 1))
                                .overlay {
                                    if selected { Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(TilezStyle.accent) }
                                }
                                .frame(height: 38)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(column * row) windows, \(column) columns, \(row) rows")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { value in
                    let point = value.location
                    guard point.x >= 0, point.y >= 0, point.x <= proxy.size.width, point.y <= proxy.size.height else { return }
                    select(column: min(columns, Int(point.x / (proxy.size.width / CGFloat(columns))) + 1),
                           row: min(rows, Int(point.y / 44) + 1))
                })
            }.frame(height: 170)
            HStack {
                Text("\(draft.count) \(draft.count == 1 ? "window" : "windows")").font(.headline).monospacedDigit()
                Spacer()
                Text(draft.columns == 0 && draft.rows == 0 ? "Automatic arrangement" : "\(draft.columns == 0 ? "Auto" : String(draft.columns)) × \(draft.rows == 0 ? "Auto" : String(draft.rows))")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Text("Click a square or drag to choose your grid.").font(.caption).foregroundStyle(.secondary)
            if grid.columns > columns || grid.rows > rows {
                Text("Custom grid extends beyond this picker. The preview shows all \(draft.count) windows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func select(column: Int, row: Int) {
        draft.columns = column
        draft.rows = row
        draft.count = column * row
    }
}

struct ArrangementOptions: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @Binding var draft: WindowSetup
    @State private var expanded = false
    @State private var defaultsSaved = false
    private var desktopDisplay: Display? {
        guard let desktop = manager.desktops.first(where: { $0.id == draft.desktop }) else { return nil }
        return Display.all.first { $0.id == desktop.displayID }
    }

    var body: some View {
        DisclosureGroup("Options", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Desktop", selection: $draft.desktop) {
                    Text("Current desktop").tag("current")
                    Text("New desktop · separate set").tag("new")
                    ForEach(manager.desktops) { desktop in Text(desktop.title).tag(desktop.id) }
                    if draft.desktop != "current" && draft.desktop != "new" && !manager.desktops.contains(where: { $0.id == draft.desktop }) {
                        Text("Saved desktop unavailable").tag(draft.desktop)
                    }
                }
                Picker("Display", selection: Binding(get: { desktopDisplay?.id ?? draft.displayID }, set: { draft.displayID = $0 })) {
                    Text("Display in use").tag("")
                    ForEach(Display.all) { display in Text(display.name).tag(display.id) }
                    if !draft.displayID.isEmpty && !Display.all.contains(where: { $0.id == draft.displayID }) {
                        Text("Saved display unavailable").tag(draft.displayID)
                    }
                }.disabled(desktopDisplay != nil)
                if desktopDisplay != nil {
                    Text("Uses the selected desktop’s display.").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Spacing · \(Int(draft.gap)) pt").font(.callout).monospacedDigit()
                    Slider(value: $draft.gap, in: 0...32, step: 1).accessibilityLabel("Window spacing")
                }
                if draft.desktop != "new" { Toggle("Open a fresh set of windows", isOn: $draft.freshWindows) }
                Toggle("Keep full-screen windows in full screen", isOn: Binding(get: { draft.keepsFullScreen }, set: { draft.preserveFullScreen = $0 }))
                Text(draft.keepsFullScreen ? "Full-screen windows count toward the total and stay in their Spaces. Only the remaining windows are tiled." : "Minimized windows are restored. Selected full-screen windows exit full screen to join the grid.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Custom window count and grid") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Windows: \(draft.count)", value: $draft.count, in: 1...40)
                        Stepper("Columns: \(draft.columns)", value: $draft.columns, in: 0...20)
                        Stepper("Rows: \(draft.rows)", value: $draft.rows, in: 0...20)
                        Text("Zero chooses automatically. Rows expand to fit the windows.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
                Divider()
                Button(defaultsSaved ? "Defaults saved" : "Use as defaults") {
                    preferences.useAsDefaults(draft)
                    defaultsSaved = true
                }.disabled(defaultsSaved)
                Text("Applies to new arrangements. Saved setups keep their own options.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 12)
        }
        .onChange(of: draft) { _, _ in defaultsSaved = false }
    }
}

struct DefaultsDisclosure: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @State private var draft: WindowSetup

    init(manager: WindowManager, preferences: Preferences) {
        self.manager = manager
        self.preferences = preferences
        _draft = State(initialValue: preferences.arrangementDraft())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrangement defaults").font(.headline)
            ArrangementOptions(manager: manager, preferences: preferences, draft: $draft)
        }
    }
}

private struct ArrangementApp: Identifiable {
    let id: String
    let name: String
    let url: URL
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Shared by the menu-bar popover, new arrangements, and saved-setup editing.
struct QuickArrangementView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    private let editing: Bool
    private let onSave: ((WindowSetup) -> Void)?
    private let preferredApp: String?
    @State private var draft: WindowSetup
    @State private var step = 0
    @State private var query = ""
    @State private var apps: [ArrangementApp] = []
    @State private var saved = false
    @State private var ran = false

    init(manager: WindowManager, preferences: Preferences, initial: WindowSetup? = nil,
         editing: Bool = false, preferredApp: String? = nil, onSave: ((WindowSetup) -> Void)? = nil) {
        self.manager = manager
        self.preferences = preferences
        self.editing = editing
        self.onSave = onSave
        self.preferredApp = preferredApp
        _draft = State(initialValue: initial ?? preferences.arrangementDraft())
    }

    private var busy: Bool { manager.openingPID != nil }
    private var desktopDisplay: Display? {
        guard let desktop = manager.desktops.first(where: { $0.id == draft.desktop }) else { return nil }
        return Display.all.first { $0.id == desktop.displayID }
    }
    private var previewBounds: CGRect {
        desktopDisplay?.bounds ?? Display.all.first { $0.id == draft.displayID }?.bounds
            ?? Display.all.first { $0.screen == NSScreen.main }?.bounds
            ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }
    private var destination: String {
        if draft.desktop == "current" { return "This desktop" }
        if draft.desktop == "new" { return "New desktop" }
        return manager.desktops.first { $0.id == draft.desktop }?.title ?? "Desktop unavailable"
    }
    private var unavailableDestination: Bool {
        (desktopDisplay == nil && !draft.displayID.isEmpty && !Display.all.contains { $0.id == draft.displayID })
            || (draft.desktop != "current" && draft.desktop != "new" && !manager.desktops.contains { $0.id == draft.desktop })
    }
    private var filteredApps: [ArrangementApp] {
        apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if step == 0 {
                Text(editing ? "Edit setup" : "Choose an arrangement").font(.title2.bold())
                if editing {
                    TextField("Setup name", text: $draft.name).textFieldStyle(.roundedBorder)
                    HStack {
                        Text(draft.appName).font(.headline)
                        Spacer()
                        Button("Change app…") { step = 1 }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ArrangementGrid(draft: $draft)
                        GridPreview(count: draft.count, columns: draft.columns, rows: draft.rows, gap: draft.gap, displayBounds: previewBounds)
                            .frame(height: 90).accessibilityElement(children: .ignore)
                            .accessibilityLabel("Arrangement preview, \(draft.count) windows")
                        ArrangementOptions(manager: manager, preferences: preferences, draft: $draft)
                    }.padding(2)
                }
                if unavailableDestination {
                    Text("This destination is unavailable. Choose another in Options.").font(.caption).foregroundStyle(.orange)
                }
                if editing && draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Give this setup a name.").font(.caption).foregroundStyle(.secondary)
                }
                Text(destinationSummary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    if editing {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave?(draft)
                    }
                    else { step = 1 }
                } label: {
                    Text(editing ? "Save changes" : "Choose app →").frame(maxWidth: .infinity)
                }.buttonStyle(TilezButtonStyle(role: .primary))
                    .disabled(busy || (editing && !draft.isValid) || (!editing && unavailableDestination))
            } else if step == 1 {
                HStack {
                    Button { step = 0 } label: { Label("Back", systemImage: "chevron.left") }
                    Spacer()
                    Text("\(draft.count) \(draft.count == 1 ? "window" : "windows")").foregroundStyle(.secondary)
                }
                Text(editing ? "Choose an app" : "Arrange \(draft.count) windows of…").font(.title2.bold())
                TextField("Find an app", text: $query).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredApps) { app in
                            Button { choose(app) } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: app.icon).resizable().frame(width: 30, height: 30)
                                    Text(app.name).lineLimit(1)
                                    Spacer()
                                    Image(systemName: editing ? "chevron.right" : "arrow.up.right").foregroundStyle(.secondary)
                                }.padding(.vertical, 6).frame(maxWidth: .infinity)
                            }.buttonStyle(TilezButtonStyle(role: .quiet, isStatic: true))
                                .disabled(busy || (!editing && !manager.trusted))
                        }
                        if filteredApps.isEmpty { Text("No matching apps").foregroundStyle(.secondary).padding() }
                    }
                }
                Button("Choose another installed app…") { chooseInstalledApp() }.disabled(busy)
                Text(destinationSummary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(draft.count) \(draft.appName) windows").font(.title2.bold())
                GridPreview(count: draft.count, columns: draft.columns, rows: draft.rows, gap: draft.gap, displayBounds: previewBounds).frame(height: 155)
                Text(destinationSummary).font(.caption).foregroundStyle(.secondary)
                Text(manager.status).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Arrangement status: \(manager.status)")
                if busy {
                    HStack { ProgressView().controlSize(.small); Button("Stop") { manager.cancelOpening() } }
                }
                Spacer(minLength: 0)
                Button {
                    manager.saveSetup(draft)
                    saved = true
                } label: { Text(saved ? "Saved to your setups" : "Save this setup").frame(maxWidth: .infinity) }
                    .buttonStyle(TilezButtonStyle(role: .primary)).disabled(saved || busy)
                HStack {
                    Button("Adjust…") { step = 0 }.disabled(busy)
                    Spacer()
                    Button("Undo") { manager.execute(.undo) }.disabled(manager.undoLabel == nil || busy)
                }
            }
            if !manager.trusted {
                Button("Allow Tilez to move windows…") { Accessibility.requestPermission(); openAccessibility() }
            }
        }.onAppear { loadApps() }
            .onChange(of: draft) { _, _ in saved = false }
    }

    private var destinationSummary: String {
        let display = desktopDisplay?.name ?? (draft.displayID.isEmpty ? "Display in use" : Display.all.first { $0.id == draft.displayID }?.name ?? "Display unavailable")
        let behavior = draft.desktop == "new" || draft.freshWindows ? "Open a separate set" : "Reuse windows; open any missing"
        return "\(destination) · \(display)\n\(behavior)" + (draft.keepsFullScreen ? " · Keep full screen" : "")
    }

    private func choose(_ app: ArrangementApp) {
        draft.bundleID = app.id
        draft.appName = app.name
        if editing { step = 0; return }
        guard manager.trusted, !busy else { return }
        // Each new run is a distinct recipe. Saving it later never replaces an older setup.
        if ran { draft.id = UUID() }
        draft.name = "\(draft.count) \(app.name) \(draft.count == 1 ? "window" : "windows")"
        saved = false
        ran = true
        step = 2
        var recent = UserDefaults.standard.stringArray(forKey: "recentArrangementApps") ?? []
        recent.removeAll { $0 == app.id }
        recent.insert(app.id, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(8)), forKey: "recentArrangementApps")
        manager.runSetup(draft)
    }

    private func loadApps() {
        var found: [String: ArrangementApp] = [:]
        func add(_ url: URL) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier,
                  !(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false),
                  !(bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool ?? false) else { return }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            found[id] = ArrangementApp(id: id, name: name, url: url)
        }
        // Shallow discovery keeps app bundles opaque and avoids walking their contents.
        for path in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "app" { add(url) }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let url = app.bundleURL { add(url) }
        }
        for setup in preferences.setups {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: setup.bundleID) { add(url) }
        }
        let recent = UserDefaults.standard.stringArray(forKey: "recentArrangementApps") ?? []
        apps = found.values.sorted {
            let lhs = $0.id == preferredApp ? -1 : recent.firstIndex(of: $0.id) ?? Int.max
            let rhs = $1.id == preferredApp ? -1 : recent.firstIndex(of: $1.id) ?? Int.max
            return lhs == rhs ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : lhs < rhs
        }
    }

    private func chooseInstalledApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        choose(ArrangementApp(id: id, name: name, url: url))
    }
}
