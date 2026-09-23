import AppKit
import SwiftUI
import TilezCore

private final class QuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// ⌃⌥N opens a Spotlight-style app search. Return opens the app as a new tile fitted into the
/// current desktop: an empty pane when there is one, otherwise the largest pane split along its
/// longer side. Every other window keeps its place. Recently added apps are listed first.
@MainActor final class QuickAddController: ObservableObject {
    @Published var query = "" { didSet { highlighted = nil } }
    @Published var highlighted: String?
    /// Its own editor model, so a quick add never touches the grid editor's draft or undo.
    let model: GridEditorModel
    private var panel: QuickAddPanel?
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    private let defaults: UserDefaults
    private static let recentsKey = "quickAddRecents"
    var isShown: Bool { panel?.isVisible == true }

    init(manager: WindowManager, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        model = GridEditorModel(manager: manager, defaults: defaults)
        model.onFinished = { [weak self] in self?.close(restoreFocus: false) }
    }

    var recents: [String] { defaults.stringArray(forKey: Self.recentsKey) ?? [] }

    var results: [GridAppChoice] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let recents = recents
        let matches = query.isEmpty ? model.apps : model.apps.filter {
            $0.app.name.localizedCaseInsensitiveContains(query) || $0.app.bundleID.localizedCaseInsensitiveContains(query)
        }
        // Recent apps first, then names that start with the query, then the catalog's own order.
        return matches.enumerated().sorted { a, b in
            func key(_ item: (offset: Int, element: GridAppChoice)) -> (Int, Int, Int) {
                (recents.firstIndex(of: item.element.id) ?? Int.max,
                 !query.isEmpty && item.element.app.name.lowercased().hasPrefix(query.lowercased()) ? 0 : 1,
                 item.offset)
            }
            return key(a) < key(b)
        }.map(\.element)
    }

    var selected: GridAppChoice? {
        let results = results
        return results.first { $0.id == highlighted } ?? results.first
    }

    func move(_ delta: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selected?.id } ?? 0
        highlighted = results[max(0, min(results.count - 1, index + delta))].id
    }

    func show(on display: Display) {
        guard !isShown, !model.busy else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        // Capture the desktop before Tilez comes forward.
        model.begin(on: display)
        query = ""; highlighted = nil
        if panel == nil {
            let panel = QuickAddPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: QuickAddView(controller: self, model: model))
            self.panel = panel
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.model.busy == false { self?.close() } }
            }
        }
        let size = CGSize(width: 620, height: 440)
        let screen = display.screen.visibleFrame
        panel?.setFrame(CGRect(x: screen.midX - size.width / 2, y: screen.maxY - screen.height * 0.18 - size.height,
                               width: size.width, height: size.height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        // The panel is reused, so focus the search field on every opening, not just the first.
        func field(in view: NSView?) -> NSTextField? {
            guard let view else { return nil }
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        if let search = field(in: panel?.contentView) { panel?.makeFirstResponder(search) }
    }

    func close(restoreFocus: Bool = true) {
        guard isShown else { return }
        model.cancel()
        model.endEditing()
        panel?.orderOut(nil)
        if restoreFocus, let previousApp, previousApp.processIdentifier != getpid() { previousApp.activate(options: []) }
    }

    func add(_ choice: GridAppChoice? = nil) {
        guard !model.busy, let choice = choice ?? selected else { return }
        remember(choice.id)
        let grid = model.grid
        if !grid.slots.contains(where: { $0.app == nil }) {
            let frames = grid.normalizedFrames
            model.selectedCell = frames.indices.max { frames[$0].width * frames[$0].height < frames[$1].width * frames[$1].height }
        }
        model.addApp()
        // addApp selects the new pane and opens its chooser; it declines when every pane is too small.
        guard model.choosingApp else { model.isError = true; return }
        model.assign(choice.app)
        model.openGrid()
    }

    private func remember(_ bundleID: String) {
        defaults.set(Array(([bundleID] + recents.filter { $0 != bundleID }).prefix(8)), forKey: Self.recentsKey)
    }
}

private struct QuickAddView: View {
    @ObservedObject var controller: QuickAddController
    @ObservedObject var model: GridEditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus.rectangle.on.rectangle").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                GridSearchField(placeholder: "Add a tile…", text: $controller.query, onSubmit: { controller.add() },
                                fontSize: 22, onMove: controller.move, onCancel: { controller.close() })
                    .frame(height: 30)
            }
            .padding(.horizontal, 20).frame(height: 64)
            Divider().opacity(0.5)
            if model.busy || (model.isError && !model.message.isEmpty) {
                HStack(spacing: 10) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.busy ? (model.message.isEmpty ? "Opening…" : model.message) : model.message)
                        .font(.system(size: 13)).foregroundStyle(model.isError ? Color.red : Color.secondary)
                    Spacer()
                }.padding(.horizontal, 20).padding(.vertical, 12)
                Divider().opacity(0.5)
            }
            results
        }
        .background {
            GridGlass(material: .popover).overlay(Color.white.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.7)))
        .preferredColorScheme(.light)
        .disabled(model.busy)
    }

    private var results: some View {
        let results = controller.results
        let recents = Set(controller.recents)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { choice in
                        let selected = controller.selected?.id == choice.id
                        Button { controller.add(choice) } label: {
                            HStack(spacing: 12) {
                                Image(nsImage: model.icon(for: choice.app)).resizable().interpolation(.high).frame(width: 30, height: 30)
                                Text(choice.app.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                Spacer()
                                if recents.contains(choice.id) {
                                    Text("Recent").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).frame(height: 44)
                            .background(Color.black.opacity(selected ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).id(choice.id)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                    if results.isEmpty {
                        Text(model.loadingApps ? "Finding apps…" : "No apps match “\(controller.query)”")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 24)
                    }
                }.padding(8)
            }
            .onChange(of: controller.highlighted) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }
}
