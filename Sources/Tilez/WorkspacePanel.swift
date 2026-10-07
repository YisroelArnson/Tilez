import AppKit
import SwiftUI
import TilezCore

private final class WorkspacePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// ⌃⌥S saves the workspace this screen shows, and ⌃⌥⇧S saves what's on screen as a new one.
/// Opening a workspace runs here too: the panel stays hidden while windows move and appears only
/// to report a problem. Browsing workspaces happens in the grid's gallery (⌃⌥W).
@MainActor final class WorkspacePanelController: ObservableObject {
    enum Mode { case save, status }
    @Published var mode = Mode.save
    @Published var name = ""
    @Published var allScreens = false
    @Published var status = ""
    @Published var isError = false
    @Published private(set) var busy = false
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

    /// From the grid's workspaces gallery or ⌃⌥1–9.
    func open(_ workspace: Workspace, on display: Display?) {
        guard !busy, let display else { return }
        self.display = display
        run(hiding: true) { store, display in
            try await store.open(workspace, from: display, progress: { _ in })
            // The workspace's first app is now active; a confirmation would take focus from it.
            return nil
        }
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
        let size = CGSize(width: 620, height: mode == .save ? 196 : 76)
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
            case .save: saveView
            case .status: statusRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The window draws the shadow; the surface only needs its glass.
        .glassSurface(RoundedRectangle(cornerRadius: 22), elevated: false)
        .preferredColorScheme(.dark)
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
