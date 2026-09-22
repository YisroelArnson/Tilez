import TilezCore
import AppKit
import SwiftUI
import ServiceManagement

enum Page: String, CaseIterable, Identifiable {
    case snapshots = "Desktop snapshots", arrange = "Arrange", active = "Active layouts", layouts = "Layouts", shortcuts = "Shortcuts", settings = "Settings", guide = "How to use"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .arrange: return "square.grid.2x2"
        case .active: return "rectangle.on.rectangle"
        case .layouts, .snapshots: return "square.stack.3d.up"
        case .shortcuts: return "command"
        case .settings: return "slider.horizontal.3"
        case .guide: return "questionmark.circle"
        }
    }
}

final class TilezNavigation: ObservableObject {
    @Published var page: Page = .layouts
    @Published var preferredApp: String?
}

struct TilezView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @ObservedObject var navigation: TilezNavigation
    let hotkeys: HotKeyCenter

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if navigation.page != .layouts {
                    Button { navigation.page = .layouts } label: { Label("Setups", systemImage: "chevron.left") }
                } else {
                    Label("Tilez", systemImage: "square.grid.2x2.fill").font(.headline).foregroundStyle(TilezStyle.accent)
                }
                Spacer()
                Menu {
                    Button("Active layouts…") { navigation.page = .active }
                    Button("Arrange selected windows…") { navigation.page = .arrange }
                    Button("Desktop snapshots…") { navigation.page = .snapshots }
                    Divider()
                    Button("Keyboard shortcuts…") { navigation.page = .shortcuts }
                    Button("How to use…") { navigation.page = .guide }
                } label: { Label("Tools", systemImage: "ellipsis.circle") }
                    .fixedSize()
                Button { navigation.page = .settings } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings").help("Settings")
            }.padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            if !manager.trusted {
                HStack(spacing: 12) {
                    Label("Allow Tilez to move windows", systemImage: "hand.raised")
                    Spacer()
                    Button("Grant Access") { Accessibility.requestPermission(); openAccessibility() }
                }.padding(16).background(.orange.opacity(0.08))
            }
            Group {
                switch navigation.page {
                case .layouts: SetupsView(manager: manager, preferences: preferences)
                case .arrange: ArrangeView(manager: manager, preferences: preferences)
                case .active: ActiveLayoutsView(manager: manager, preferences: preferences)
                case .snapshots: SnapshotsView(manager: manager, preferences: preferences)
                case .shortcuts: ShortcutsView(manager: manager, preferences: preferences, hotkeys: hotkeys)
                case .settings: SettingsView(manager: manager, preferences: preferences)
                case .guide: GuideView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack(spacing: 10) {
                if manager.openingPID != nil { ProgressView().controlSize(.small) }
                Text(manager.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Spacer(minLength: 0)
                if manager.openingPID != nil {
                    Button("Stop") { manager.cancelOpening() }
                } else {
                    Button("Undo", systemImage: "arrow.uturn.backward") { manager.execute(.undo) }
                        .disabled(manager.undoLabel == nil)
                }
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }.frame(minWidth: 650, minHeight: 620)
            .background(Color(nsColor: .windowBackgroundColor))
            .buttonStyle(TilezButtonStyle()).tint(TilezStyle.accent)
    }
}

func openAccessibility() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}

private struct ArrangeView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @State private var selectedPID: pid_t?
    @State private var selected: Set<String> = []
    @State private var customGrid = false
    @State private var showBehavior = false
    @State private var editing: WindowSetup?
    @State private var hasNewWindowCommand = true

    private var group: AppGroup? { manager.groups.first { $0.pid == selectedPID } }
    private var selectedWindows: [ManagedWindow] { group?.windows.filter { selected.contains($0.id) } ?? [] }
    private var busy: Bool { manager.openingPID != nil }
    private var destinationLabel: String {
        if preferences.desktop == "new" { return "New desktop" }
        if preferences.desktop == "current" { return "Current desktop" }
        return manager.desktops.first { $0.id == preferences.desktop }?.title ?? "Desktop unavailable"
    }
    private var behaviorLabel: String {
        let reuse = preferences.desktop == "new" || preferences.freshWindows ? "Fresh windows" : "Reuse existing windows"
        return reuse + (preferences.preserveFullScreen ? " · Keep full screen" : " · Exit full screen to tile")
    }
    private var previewBounds: CGRect {
        Display.all.first { $0.id == preferences.gatherDisplay }?.bounds
            ?? Display.all.first?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Arrange windows").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Choose your app, window count, and a place for them.").foregroundStyle(.secondary)
                    }
                    appPicker
                    if let group { configuration(group) }
                    gridControls
                    if let group { windowSelection(group) }
                    else {
                        ContentUnavailableView("Choose an app to begin", systemImage: "macwindow.badge.plus",
                            description: Text(manager.trusted ? "Select a running app above, or open another app." : "Grant Accessibility access to discover your windows."))
                    }
                }.padding(24)
            }
            if let group { actionBar(group) }
        }
        .sheet(item: $editing) { setup in
            SetupEditor(manager: manager, initial: setup) { manager.saveSetup($0); editing = nil }
        }
        .onAppear {
            customGrid = preferences.columns > 0 || preferences.rows > 0
            if selectedPID == nil {
                selectedPID = manager.groups.first(where: {
                    NSRunningApplication(processIdentifier: $0.pid)?.bundleIdentifier == "com.openai.codex"
                        || $0.name.localizedCaseInsensitiveContains("chatgpt")
                })?.pid ?? manager.groups.first?.pid
            }
            selectAll(); updateCapability()
        }
        .onChange(of: selectedPID) { _, _ in selectAll(); updateCapability() }
        .onChange(of: manager.preparedWindowIDs) { _, ids in
            if !ids.isEmpty { selected = Set(ids) }
        }
        .onChange(of: manager.groups.map(\.pid)) { _, ids in
            if selectedPID == nil || !ids.contains(selectedPID!) { selectedPID = ids.first; selectAll() }
        }
        .onChange(of: customGrid) { _, custom in
            if !custom { preferences.columns = 0; preferences.rows = 0 }
            else if preferences.columns == 0 && preferences.rows == 0 { preferences.columns = 3 }
        }
    }

    private var appPicker: some View {
        HStack(spacing: 10) {
            Picker("App", selection: $selectedPID) {
                Text("Choose an app").tag(nil as pid_t?)
                ForEach(manager.groups) { group in
                    Text("\(group.name) · \(group.windows.count) open").tag(Optional(group.pid))
                }
            }
            Button("Open app…", systemImage: "plus.app") { chooseApp() }
            Button { manager.refresh(); updateCapability() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(TilezButtonStyle(role: .quiet, iconOnly: true))
                .accessibilityLabel("Refresh windows").help("Refresh windows")
        }.disabled(busy)
    }

    private func configuration(_ group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TilezSectionLabel(title: "HOW MANY WINDOWS?", symbol: "macwindow.badge.plus")
                Spacer()
                Stepper(value: $preferences.desiredWindows, in: 1...40) {
                    Text("\(preferences.desiredWindows)").font(.title2.weight(.semibold)).monospacedDigit()
                }.fixedSize().accessibilityLabel("Window count")
            }
            HStack(spacing: 8) {
                ForEach([1, 2, 4, 6, 8], id: \.self) { count in
                    Button { preferences.desiredWindows = count } label: {
                        Text("\(count)").monospacedDigit().frame(maxWidth: .infinity)
                    }.buttonStyle(TilezButtonStyle(role: preferences.desiredWindows == count ? .primary : .secondary, isStatic: true))
                        .accessibilityLabel("\(count) \(count == 1 ? "window" : "windows")")
                        .accessibilityAddTraits(preferences.desiredWindows == count ? .isSelected : [])
                }
            }
            Picker("Desktop", selection: $preferences.desktop) {
                Text("Current desktop").tag("current")
                Text("New desktop · separate set").tag("new")
                ForEach(manager.desktops) { desktop in Text(desktop.title).tag(desktop.id) }
                if preferences.desktop != "new" && preferences.desktop != "current" && !manager.desktops.contains(where: { $0.id == preferences.desktop }) {
                    Text("Saved desktop unavailable").tag(preferences.desktop)
                }
            }
            Picker("Display", selection: $preferences.gatherDisplay) {
                Text("Keep current displays").tag("")
                ForEach(Display.all) { display in Text(display.name).tag(display.id) }
                if !preferences.gatherDisplay.isEmpty && !Display.all.contains(where: { $0.id == preferences.gatherDisplay }) {
                    Text("Saved display unavailable").tag(preferences.gatherDisplay)
                }
            }
            if preferences.desktop == "new" {
                Label("A separate set. Swipe between desktops to return to your other windows.", systemImage: "rectangle.on.rectangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            DisclosureGroup(isExpanded: $showBehavior) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Keep full-screen windows in full screen", isOn: $preferences.preserveFullScreen)
                    Text(preferences.preserveFullScreen
                         ? "Full-screen windows count toward the total and stay in their own Spaces. The rest are tiled."
                         : "Minimized windows are restored. Full-screen windows leave full screen before tiling.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preferences.desktop != "new" {
                        Toggle("Open a fresh set of windows", isOn: $preferences.freshWindows)
                    }
                }.padding(.top, 10)
            } label: {
                Text(behaviorLabel).font(.caption).foregroundStyle(.secondary)
            }
            if !hasNewWindowCommand {
                Label("\(group.name) has no New Window command. Existing windows can be restored; extra windows may not be supported.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if preferences.desiredWindows > max(1, group.windows.count) {
                    Button("Use \(max(1, group.windows.count)) available") { preferences.desiredWindows = max(1, group.windows.count) }
                }
            }
        }.tilezSurface(tinted: true).disabled(busy)
    }

    private var gridControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TilezSectionLabel(title: "ARRANGEMENT", symbol: "square.grid.3x2")
                Spacer()
                Picker("Grid", selection: $customGrid) {
                    Text("Automatic").tag(false)
                    Text("Custom").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
            }
            if customGrid {
                HStack(spacing: 18) {
                    Stepper("Columns: \(preferences.columns == 0 ? "Auto" : String(preferences.columns))", value: $preferences.columns, in: 0...20)
                    Stepper("Rows: \(preferences.rows == 0 ? "Auto" : String(preferences.rows))", value: $preferences.rows, in: 0...20)
                }
                Text("Rows expand to fit. Zero lets Tilez choose.").font(.caption).foregroundStyle(.secondary)
            }
            GridPreview(count: preferences.desiredWindows, columns: preferences.columns, rows: preferences.rows,
                        gap: preferences.gap, displayBounds: previewBounds)
                .frame(height: 108)
                .background(TilezStyle.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: TilezStyle.innerRadius))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of \(preferences.desiredWindows) windows, \(customGrid ? "custom" : "automatic") arrangement")
            HStack {
                Text("Spacing").font(.callout)
                Slider(value: $preferences.gap, in: 0...32, step: 1).accessibilityLabel("Window spacing")
                Text("\(Int(preferences.gap)) pt").monospacedDigit().frame(width: 42)
            }
        }.tilezSurface().disabled(busy)
    }

    private func windowSelection(_ group: AppGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open windows").font(.headline)
                    Text("\(selectedWindows.count) of \(group.windows.count) selected").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("All") { selectAll() }.buttonStyle(TilezButtonStyle(role: .quiet, isStatic: true))
                Button("None") { selected = [] }.buttonStyle(TilezButtonStyle(role: .quiet, isStatic: true))
            }
            if group.windows.isEmpty {
                Label("No windows yet. Open & Tile will try to open them.", systemImage: "macwindow.badge.plus")
                    .foregroundStyle(.secondary).padding(.vertical, 16)
            }
            ForEach(group.windows) { window in
                TilezWindowRow(window: window, selected: Binding(get: { selected.contains(window.id) }, set: { value in
                    if value { selected.insert(window.id) } else { selected.remove(window.id) }
                }))
            }
            if !group.windows.isEmpty {
                HStack {
                    Text("Tile these on their desktops without opening more.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Tile selected (\(selectedWindows.count))") { manager.tile(pid: group.pid, selected: selected) }
                        .disabled(selectedWindows.isEmpty || !manager.trusted)
                }
                Divider()
                Toggle("Keep arranged as windows open or close", isOn: Binding(get: { manager.watched.contains(group.pid) }, set: { _ in manager.toggleWatch(group.pid) }))
                    .toggleStyle(.switch).font(.callout)
                Text("Watch includes all visible windows outside full screen. Resets when the app or Tilez quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.tilezSurface().disabled(busy)
    }

    private func actionBar(_ group: AppGroup) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(preferences.desiredWindows) \(group.name) \(preferences.desiredWindows == 1 ? "window" : "windows")").font(.callout.weight(.semibold)).lineLimit(1)
                    Text(destinationLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(destinationLabel)
                }
                Spacer(minLength: 0)
                Button("Save setup…", systemImage: "bookmark") { prepareSetup(group) }.disabled(busy)
                Button {
                    if manager.openingPID == group.pid { manager.cancelOpening() }
                    else { manager.openAndTile(pid: group.pid, count: preferences.desiredWindows, preferredIDs: selected) }
                } label: {
                    HStack(spacing: 8) {
                        if manager.openingPID == group.pid { ProgressView().controlSize(.small) }
                        else { Image(systemName: "square.grid.3x2") }
                        Text(manager.openingPID == group.pid ? "Cancel opening" : "Open & Tile")
                    }.frame(minWidth: 120)
                }.buttonStyle(TilezButtonStyle(role: manager.openingPID == group.pid ? .secondary : .primary, isStatic: manager.openingPID == group.pid))
                    .disabled(!manager.trusted || (busy && manager.openingPID != group.pid))
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    private func prepareSetup(_ group: AppGroup) {
        guard let bundle = NSRunningApplication(processIdentifier: group.pid)?.bundleIdentifier else {
            manager.status = "This app does not expose an identifier for saved setups."; return
        }
        editing = WindowSetup(name: "\(preferences.desiredWindows) \(group.name) windows", bundleID: bundle, appName: group.name,
            count: preferences.desiredWindows, columns: preferences.columns, rows: preferences.rows, gap: preferences.gap,
            displayID: preferences.gatherDisplay, desktop: preferences.desktop, freshWindows: preferences.freshWindows, preserveFullScreen: preferences.preserveFullScreen)
    }
    private func updateCapability() {
        hasNewWindowCommand = selectedPID.map { Accessibility.newWindowCommand(pid: $0) != nil } ?? true
    }
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                manager.refresh(); selectedPID = app.processIdentifier
                selectAll(); updateCapability()
                manager.status = "Opened \(app.localizedName ?? "app"). Choose its window count and arrangement."
            } catch { manager.status = error.localizedDescription }
        }
    }
    private func selectAll() { selected = Set(group?.windows.map(\.id) ?? []) }
}

struct GridPreview: View {
    let count: Int
    let columns: Int
    let rows: Int
    let gap: Double
    let displayBounds: CGRect
    private func frames(in size: CGSize) -> [CGRect] {
        let scale: CGFloat = min(size.width / displayBounds.width, size.height / displayBounds.height)
        let frames = TilezCore.Geometry.grid(count: count, in: CGRect(origin: .zero, size: displayBounds.size), columns: columns, rows: rows, gap: gap)
        let offsetX: CGFloat = (size.width - displayBounds.width * scale) / 2
        return frames.map { rect in
            CGRect(x: offsetX + rect.minX * scale, y: rect.minY * scale,
                   width: max(1, rect.width * scale - 2), height: max(1, rect.height * scale - 2))
        }
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames(in: proxy.size).enumerated()), id: \.offset) { index, rect in
                    PreviewTile(index: index, rect: rect)
                }
            }
        }.padding(10)
    }
}

private struct PreviewTile: View {
    let index: Int
    let rect: CGRect
    var body: some View {
        RoundedRectangle(cornerRadius: 5).fill(TilezStyle.accent.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(TilezStyle.accent.opacity(0.35)))
            .overlay(Text("\(index + 1)").font(Font.caption.weight(.medium)).foregroundStyle(TilezStyle.accent))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

struct SnapshotsView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @State private var name = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Desktop snapshots").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Save positions across all apps and displays. Restore a layout whenever you need it.").foregroundStyle(.secondary)
                HStack {
                    TextField("Layout name, e.g. Six Codex windows", text: $name).textFieldStyle(.roundedBorder)
                        .onSubmit { save() }
                    Button("Save Desktop") { save() }.buttonStyle(TilezButtonStyle(role: .primary)).disabled(!manager.trusted)
                }
                if preferences.layouts.isEmpty {
                    ContentUnavailableView("No saved layouts yet", systemImage: "square.stack.3d.up", description: Text("Arrange your windows, then save your desktop here."))
                }
                ForEach(preferences.layouts) { layout in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Name", text: Binding(get: { preferences.layouts.first { $0.id == layout.id }?.name ?? "" },
                                                           set: { value in if let i = preferences.layouts.firstIndex(where: { $0.id == layout.id }) { preferences.layouts[i].name = value } }))
                                .textFieldStyle(.plain).font(.headline)
                            Spacer()
                            Button("Restore") { manager.restore(layout) }.disabled(!manager.trusted)
                            Button(role: .destructive) { preferences.layouts.removeAll { $0.id == layout.id } } label: { Image(systemName: "trash") }.help("Delete layout")
                        }
                        Text("\(layout.windows.count) windows · \(layout.created.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Restore automatically when this display setup returns",
                               isOn: Binding(get: { preferences.layouts.first { $0.id == layout.id }?.autoRestore ?? false },
                                             set: { manager.pinLayout(layout.id, enabled: $0) }))
                            .font(.caption)
                    }.tilezSurface()
                }
                Text("Restore matches open windows by app and title, then by position in the app’s window list. It does not launch apps or reopen documents. Identical titles may be matched in a different order after an app restarts.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(26)
        }
    }
    private func save() { manager.saveLayout(name: name); name = "" }
}

private struct ShortcutsView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    let hotkeys: HotKeyCenter
    @State private var message = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Make it a keystroke.").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Click a shortcut to record it. Include Control, Option, or Command. Escape cancels; Delete disables.")
                    .foregroundStyle(.secondary)
                if !message.isEmpty { Text(message).foregroundStyle(.orange).font(.caption) }
                if !manager.shortcutError.isEmpty { Text(manager.shortcutError).foregroundStyle(.orange).font(.caption) }
                ForEach(Command.allCases) { command in
                    HStack {
                        Text(command.title)
                        Spacer()
                        ShortcutRecorder(shortcut: preferences.shortcut(command), onRecord: { shortcut in
                            let duplicate = Command.allCases.first { $0 != command && preferences.shortcut($0).key == shortcut.key && preferences.shortcut($0).modifiers == shortcut.modifiers && shortcut.modifiers != 0 }
                            if let duplicate { message = "That shortcut is already assigned to \(duplicate.title)." }
                            else { preferences.shortcuts[command.rawValue] = shortcut; message = "" }
                        }, onRecording: { hotkeys.suspended = $0 }).frame(width: 155, height: 28)
                    }
                    Divider()
                }
                Button("Restore Default Shortcuts") { preferences.shortcuts = [:]; hotkeys.register(); message = "" }
            }.padding(26)
        }
        .onDisappear { hotkeys.suspended = false }
    }
}

private struct SettingsView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    @State private var inputAllowed = CGPreflightListenEventAccess()
    var body: some View {
        Form {
            Section {
                DefaultsDisclosure(manager: manager, preferences: preferences)
            }
            Section("Window behavior") {
                Toggle("Snap dragged windows at screen edges", isOn: $preferences.edgeSnap)
                Text("Drag left or right for halves, into corners for quarters, to the top to maximize, or to the bottom for the lower half. Release to apply the preview.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Two-finger swipes on title bars", isOn: $preferences.titleSwipe)
                Text("Swipe left or right for halves, up to maximize, down to center. Uses trackpad scrolling gestures over the top 38 points of a standard title bar; custom title bars may behave differently.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(inputAllowed ? "Input Monitoring is enabled" : "Input Monitoring for trackpad gestures").font(.caption)
                    Spacer()
                    Button("Enable Input Monitoring") {
                        _ = CGRequestListenEventAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        inputAllowed = CGPreflightListenEventAccess()
                    }
                }
                Toggle("Remember manual moves for Undo", isOn: $preferences.undoManual)
                Text("Keeps up to 50 recent arrangements in memory. Undo is cleared when Tilez quits.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch Tilez at login", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = ""
                        } catch { loginError = error.localizedDescription }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                    }
                if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
            Section("Access & privacy") {
                HStack {
                    Label(manager.trusted ? "Accessibility enabled" : "Accessibility required", systemImage: manager.trusted ? "checkmark.shield" : "hand.raised")
                    Spacer()
                    Button("Open System Settings") { openAccessibility() }
                }
                Text("Tilez works entirely on your Mac. No accounts, analytics, network requests, or screen recording. Saved layouts keep app identifiers, window titles, and positions locally.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tilez 1.7.1") {
                Text("A native window manager, built for your workspace.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct GuideView: View {
    private let sections: [(String, String, String)] = [
        ("square.grid.2x2", "One click to tile", "Click the Tilez icon in your menu bar. Open a saved setup, or choose New arrangement, click or drag a grid, and choose an app. The same flow is available in the main window."),
        ("macwindow.badge.plus", "Choose how many windows", "A 3 × 2 grid requests six windows. Tilez reuses eligible windows on the destination desktop and opens any missing ones. Extra windows stay open. Choose from installed apps using the searchable icon list. Apps without a New Window command may require you to open additional windows manually."),
        ("rectangle.on.rectangle", "Separate desktops and saved setups", "Expand Options to choose a desktop, display, spacing, or window behavior. New desktop opens a separate set. Use as defaults remembers these choices for future arrangements; saved setups keep their own options. Desktop control is experimental and needs macOS 26.4 or later for cross-desktop moves; Mission Control may appear briefly."),
        ("eye", "Keep it in order", "In Tools → Arrange selected windows, enable Watch for an app. Tilez retiles when its eligible windows open, close, minimize, or return. Watch applies to all its eligible windows and resets when the app or Tilez quits."),
        ("command", "Snap with your keyboard", "Control–Option–arrow snaps a window. Repeat within two seconds to cycle half, one third, and two thirds. U/I/J/K select corners; D/F/G select thirds. Return maximizes; C centers. All shortcuts are editable."),
        ("hand.draw", "Draw your own space", "Press Control–Option–Space while a window is focused. Draw on the display under your pointer, then release. The rectangle snaps to a 24 × 16 guide. Escape cancels."),
        ("arrow.up.left.and.arrow.down.right", "Drag or swipe", "Drag a window to a screen edge and release when you see the preview. Optional two-finger title-bar swipes snap left/right, maximize upward, and center downward."),
        ("display.2", "Move between displays", "Control–Option–] and [ move the focused window to the next or previous display while preserving its relative size and position."),
        ("square.stack.3d.up", "Save a workspace", "After arranging, choose Save this setup for a reusable app arrangement. Setup cards run with one click; their menu contains Edit, Duplicate, and Delete. Tools → Desktop snapshots captures existing window positions across apps. Snapshots require those apps and documents to be open."),
        ("arrow.uturn.backward", "Change your mind", "Control–Option–Z undoes a grid, snap, restore, or a manual window move observed while Tilez is running."),
        ("info.circle", "A few practical details", "Tilez lists normal, minimized, hidden, full-screen, and fixed-size app windows. Dialogs are excluded. Tiling restores selected windows and waits for full-screen exit; enable Keep full-screen windows to preserve their Spaces. Watch only arranges visible, resizable windows outside full screen. Some apps expose windows from other Spaces. App minimum sizes can prevent a dense grid from fitting; Tilez reports this in its status bar.")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Meet your new workspace.").font(.system(size: 26, weight: .bold, design: .rounded))
                ForEach(sections, id: \.0) { symbol, title, detail in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: symbol).font(.title2).foregroundStyle(TilezStyle.accent).frame(width: 30)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(.headline)
                            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }.padding(26)
        }
    }
}
