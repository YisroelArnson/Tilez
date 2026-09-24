import AppKit
import SwiftUI
import TilezCore

private final class WorkspacePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// ⌃⌥W lists workspaces to open; ⌃⌥S saves the one this screen shows, and ⌃⌥⇧S saves what's on
/// screen as a new one. The panel hides while windows move and returns only to report a problem.
@MainActor final class WorkspacePanelController: ObservableObject {
    enum Mode { case open, save, status }
    @Published var mode = Mode.open
    @Published var query = "" { didSet { highlighted = nil } }
    @Published var highlighted: UUID?
    @Published var name = ""
    @Published var allScreens = false
    @Published var status = ""
    @Published var isError = false
    @Published private(set) var busy = false
    @Published private(set) var listed: [Workspace] = []
    /// The workspace the screen shows when the panel opened.
    @Published private(set) var shownID: UUID?
    @Published var renamingID: UUID?
    @Published var renameText = ""
    let store: WorkspaceStore
    /// Puts back an enlarged window on that screen before its layout is read or changed.
    var prepare: ((Display) async -> Void)?
    private var panel: WorkspacePanel?
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    private var display: Display?
    private var task: Task<Void, Never>?
    private var closeWork: DispatchWorkItem?
    private var escapeMonitor: Any?
    var isShown: Bool { panel?.isVisible == true }
    var hasMultipleScreens: Bool { Display.all.count > 1 }

    init(store: WorkspaceStore) { self.store = store }

    var results: [Workspace] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? listed : listed.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    var selected: Workspace? { results.first { $0.id == highlighted } ?? results.first }

    func move(_ delta: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selected?.id } ?? 0
        highlighted = results[max(0, min(results.count - 1, index + delta))].id
    }

    func showList(on display: Display) {
        guard !busy else { return }
        listed = store.current()
        shownID = store.shownWorkspace(on: display)?.id
        query = ""; highlighted = nil; renamingID = nil
        present(.open, on: display)
    }

    /// The list with one workspace's name ready to edit.
    func showRename(_ id: UUID, on display: Display) {
        showList(on: display)
        beginRename(id)
    }

    /// The list's order is the ⌃⌥1–9 numbering. Reordering needs the whole list, not a search.
    var canReorder: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func reorder(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard canReorder else { return }
        store.move(fromOffsets: source, toOffset: destination)
        listed = store.workspaces
    }

    /// ⌘↑/⌘↓ moves the highlighted workspace, keeping it highlighted.
    func moveSelected(_ delta: Int) {
        guard canReorder, let id = selected?.id else { return }
        store.move(id, by: delta)
        listed = store.workspaces
        highlighted = id
    }

    func beginRename(_ id: UUID) {
        guard let workspace = listed.first(where: { $0.id == id }) else { return }
        highlighted = id
        renameText = workspace.name
        renamingID = id
    }

    func commitRename() {
        guard let id = renamingID else { return }
        if store.rename(id, to: renameText) {
            listed = store.workspaces
            endRename()
        } else {
            NSSound.beep()
        }
    }

    /// Typing goes back to the search field.
    func endRename() {
        renamingID = nil
        DispatchQueue.main.async { [weak self] in
            func field(in view: NSView?) -> NSTextField? {
                guard let view else { return nil }
                if let field = view as? NSTextField, field.isEditable { return field }
                return view.subviews.lazy.compactMap { field(in: $0) }.first
            }
            if let search = field(in: self?.panel?.contentView) { self?.panel?.makeFirstResponder(search) }
        }
    }

    /// Its position in the list, while it has a ⌃⌥ shortcut.
    func number(of workspace: Workspace) -> Int? {
        store.workspaces.firstIndex { $0.id == workspace.id }.flatMap { $0 < 9 ? $0 + 1 : nil }
    }

    func showSave(on display: Display) {
        guard !busy else { return }
        _ = store.current()
        name = store.suggestedName
        allScreens = false
        present(.save, on: display)
    }

    /// ⌃⌥S: saves the shown workspace in place, or asks for a name when there isn't one.
    func quickSave(on display: Display) {
        guard !busy else { return }
        guard store.shownWorkspace(on: display) != nil else { showSave(on: display); return }
        self.display = display
        run(hiding: false) { store, display in
            "Saved workspace “\(try await store.saveShown(on: display).name)”"
        }
    }

    func save() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !name.isEmpty else { return }
        let allScreens = allScreens && hasMultipleScreens
        run(hiding: false) { store, display in
            "Saved workspace “\(try await store.saveNew(named: name, allScreens: allScreens, from: display).name)”"
        }
    }

    func open(_ workspace: Workspace? = nil) {
        guard !busy, let workspace = workspace ?? selected else { return }
        open(workspace, on: display)
    }

    /// Also used by the grid's Open list.
    func open(_ workspace: Workspace, on display: Display?) {
        guard !busy, let display else { return }
        self.display = display
        run(hiding: true) { store, display in
            try await store.open(workspace, from: display, progress: { _ in })
            // The workspace's first app is now active; a confirmation would take focus from it.
            return nil
        }
    }

    func delete(_ id: UUID) {
        store.remove(id)
        listed = store.current()
        if renamingID == id { renamingID = nil }
        if shownID == id { shownID = nil }
    }

    /// Runs one workspace action. Success closes the panel, after a moment when there's
    /// something to confirm; a failure shows why.
    private func run(hiding: Bool, _ action: @escaping (WorkspaceStore, Display) async throws -> String?) {
        guard let display else { return }
        closeWork?.cancel()
        busy = true; isError = false; status = ""
        if hiding { panel?.orderOut(nil) } else { status = "Saving…"; present(.status, on: display) }
        task = Task { [weak self] in
            await self?.prepare?(display)
            guard let self else { return }
            do {
                let message = try await action(self.store, display)
                self.busy = false
                if let message {
                    self.status = message
                    if !self.isShown { self.present(.status, on: display) }
                    self.mode = .status
                    self.scheduleClose(after: 1.2)
                } else { self.close(restoreFocus: false) }
            } catch {
                self.busy = false
                if error is CancellationError { self.close(restoreFocus: false); return }
                self.status = error.localizedDescription; self.isError = true
                self.present(.status, on: display)
            }
        }
    }

    private func scheduleClose(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if self?.busy == false && self?.isError == false { self?.close() } }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func present(_ mode: Mode, on display: Display) {
        closeWork?.cancel()
        if !isShown { previousApp = NSWorkspace.shared.frontmostApplication }
        self.mode = mode
        self.display = display
        if panel == nil {
            let panel = WorkspacePanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: WorkspacePanelView(controller: self))
            self.panel = panel
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.busy == false { self?.close(restoreFocus: false) } }
            }
            // The text fields handle Escape themselves; a status message has no field to focus.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53, event.window === self.panel, self.mode == .status else { return event }
                self.cancel()
                return nil
            }
        }
        let size = CGSize(width: 620, height: mode == .open ? 460 : mode == .save ? 196 : 76)
        let screen = display.screen.visibleFrame
        panel?.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.maxY - screen.height * 0.18 - size.height,
                               width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func close(restoreFocus: Bool = true) {
        closeWork?.cancel()
        guard isShown else { return }
        panel?.orderOut(nil)
        if restoreFocus, let previousApp, previousApp.processIdentifier != getpid() { previousApp.activate(options: []) }
    }

    func cancel() {
        if busy { task?.cancel() } else { close() }
    }
}

private struct WorkspacePanelView: View {
    @ObservedObject var controller: WorkspacePanelController

    var body: some View {
        VStack(spacing: 0) {
            switch controller.mode {
            case .open: openView
            case .save: saveView
            case .status: statusRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            GridGlass(material: .popover).overlay(Color.white.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.7)))
        .preferredColorScheme(.light)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            if controller.busy { ProgressView().controlSize(.small) }
            else {
                Image(systemName: controller.isError ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(controller.isError ? Color.red : Color.primary)
            }
            Text(controller.status).font(.system(size: 14, weight: .medium)).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 22).frame(height: 76)
    }

    private var openView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                GridSearchField(placeholder: "Open a workspace…", text: $controller.query, onSubmit: { controller.open() },
                                fontSize: 22, onMove: controller.move, onCancel: { controller.close() },
                                onReorder: controller.moveSelected)
                    .frame(height: 30)
            }
            .padding(.horizontal, 20).frame(height: 64)
            Divider().opacity(0.5)
            list
            Divider().opacity(0.5)
            Text("↵  Open   ·   Drag or ⌘↑ ⌘↓  Reorder, which renumbers ⌃⌥1–9   ·   ⌃⌥⇧S  Save new   ·   Esc  Close")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 30)
        }
    }

    private var list: some View {
        let results = controller.results
        let controller = controller
        let reorder: ((IndexSet, Int) -> Void)? = controller.canReorder ? { controller.reorder(fromOffsets: $0, toOffset: $1) } : nil
        return ScrollViewReader { proxy in
            List {
                ForEach(results) { workspace in
                    row(workspace, selected: controller.selected?.id == workspace.id)
                        .id(workspace.id)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                }
                .onMove(perform: reorder)
                if results.isEmpty {
                    Text(controller.listed.isEmpty ? "No workspaces yet. Press ⌃⌥⇧S to save the windows on this screen as one."
                                                   : "No workspaces match “\(controller.query)”")
                        .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).padding(.vertical, 6)
            .onChange(of: controller.highlighted) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    /// Clicking opens it; dragging the row reorders the list.
    private func row(_ workspace: Workspace, selected: Bool) -> some View {
        let renaming = controller.renamingID == workspace.id
        return HStack(spacing: 10) {
            Text(controller.number(of: workspace).map { "\($0)" } ?? "")
                .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                .frame(width: 14)
            WorkspaceThumbnail(workspace: workspace, height: 30, maxWidth: 96).frame(width: 96)
            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    GridSearchField(placeholder: "Workspace name", text: $controller.renameText, onSubmit: controller.commitRename,
                                    fontSize: 15, onCancel: controller.endRename)
                        .frame(height: 20)
                } else {
                    Text(workspace.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                }
                Text(summary(workspace)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if controller.shownID == workspace.id {
                Text("On this screen").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            if let number = controller.number(of: workspace) {
                Text("⌃⌥\(number)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            Button { renaming ? controller.commitRename() : controller.beginRename(workspace.id) } label: {
                Image(systemName: renaming ? "checkmark" : "pencil").frame(width: 24, height: 28)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(renaming ? "Save name" : "Rename")
            .accessibilityLabel(renaming ? "Save name" : "Rename \(workspace.name)")
            Button { controller.delete(workspace.id) } label: { Image(systemName: "trash").frame(width: 24, height: 28) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete workspace")
                .accessibilityLabel("Delete \(workspace.name)")
        }
        .padding(.horizontal, 10).frame(height: 50)
        .background(Color.black.opacity(selected ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { if !renaming { controller.open(workspace) } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAction { controller.open(workspace) }
    }

    private func summary(_ workspace: Workspace) -> String {
        let apps = workspace.screens.flatMap { $0.grid.slots.compactMap(\.app?.name) }
        var unique: [String] = []
        for app in apps where !unique.contains(app) { unique.append(app) }
        let windows = "\(workspace.windowCount) window\(workspace.windowCount == 1 ? "" : "s")"
        let screens = workspace.screens.count > 1 ? " on \(workspace.screens.count) screens" : ""
        return "\(windows)\(screens) · \(unique.joined(separator: ", "))"
    }

    private var saveView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.3.group").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                GridSearchField(placeholder: "Workspace name", text: $controller.name, onSubmit: controller.save,
                                fontSize: 22, onCancel: { controller.close() })
                    .frame(height: 30)
            }
            .frame(height: 40)
            if controller.hasMultipleScreens {
                Picker("Save", selection: $controller.allScreens) {
                    Text("This screen").tag(false)
                    Text("All screens").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
            }
            HStack {
                Text("Keeps these exact windows. Closed windows leave it; nothing reopens.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Save", action: controller.save).buttonStyle(GridButtonStyle(primary: true))
                    .disabled(controller.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
    }
}
