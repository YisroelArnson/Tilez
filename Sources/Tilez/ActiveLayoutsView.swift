import AppKit
import SwiftUI
import TilezCore

struct ActiveLayoutsView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @State private var query = ""
    @State private var editing: RunningLayout?
    @State private var closing: RunningLayout?
    private var layouts: [RunningLayout] {
        manager.runningLayouts.filter {
            query.isEmpty || ($0.record.setup.name + " " + $0.record.setup.appName + " " + $0.location).localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Active layouts").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Manage each set of open windows together.").foregroundStyle(.secondary)
            }
            HStack {
                TextField("Find an app or layout", text: $query).textFieldStyle(.roundedBorder)
                Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(TilezButtonStyle(role: .quiet, iconOnly: true)).accessibilityLabel("Refresh active layouts")
            }
            if manager.openingPID != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(manager.status).font(.callout).lineLimit(2)
                    Spacer()
                    Button("Stop") { manager.cancelOpening() }
                }.padding(12).background(TilezStyle.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            ScrollView {
                LazyVStack(spacing: 14) {
                    if layouts.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "No active layouts" : "No matching layouts", systemImage: "rectangle.on.rectangle",
                            description: Text(query.isEmpty ? "Open a setup or use Arrange. Existing windows also appear here by app and desktop." : "Try another app name or clear your search."))
                    }
                    ForEach(layouts) { layout in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(spacing: 0) {
                                    Text("\(layout.windows.count)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                                    Text(layout.windows.count == 1 ? "window" : "windows").font(.caption2)
                                }.foregroundStyle(TilezStyle.accent).frame(width: 68, height: 60)
                                    .background(TilezStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(layout.record.setup.name).font(.headline).lineLimit(1)
                                    Text(layout.location).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    Text(layout.detected ? "Detected by app and desktop" : "Tracked set · \(layout.record.setup.appName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            HStack {
                                Text(layout.windows.prefix(2).map { $0.title.isEmpty ? "Untitled window" : $0.title }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 12)
                                Button("Edit…", systemImage: "slider.horizontal.3") { editing = layout }
                                    .accessibilityIdentifier("edit-\(layout.id)")
                                Button("Close set…", systemImage: "xmark") { closing = layout }
                                    .buttonStyle(TilezButtonStyle(role: .destructive))
                                    .accessibilityIdentifier("close-\(layout.id)")
                            }.disabled(manager.openingPID != nil || !manager.trusted)
                        }.tilezSurface()
                    }
                }.padding(2)
            }
            Text("Detected sets group existing windows by app and desktop. New layouts remember their exact windows, even on the same desktop.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        .sheet(item: $editing) { layout in
            ActiveLayoutEditor(manager: manager, layout: layout) { setup, keeping in
                editing = nil
                manager.changeActiveLayout(layout, setup: setup, keeping: keeping)
            }
        }
        .alert("Close this set of windows?", isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } })) {
            Button("Cancel", role: .cancel) { closing = nil }
            Button("Close \(closing?.windows.count ?? 0) windows", role: .destructive) {
                guard let layout = closing else { return }
                closing = nil
                manager.changeActiveLayout(layout, setup: layout.record.setup, keeping: [], closeAll: true)
            }
        } message: {
            if let layout = closing {
                Text("\(layout.record.setup.name) · \(layout.location)\n\nOnly these \(layout.windows.count) windows will close. This cannot be undone by Tilez. Any save prompt will stop the operation; other sets stay open.")
            }
        }
    }
}

private struct ActiveLayoutEditor: View {
    @ObservedObject var manager: WindowManager
    let layout: RunningLayout
    let onApply: (WindowSetup, Set<String>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WindowSetup
    @State private var keeping: Set<String>
    @State private var confirmReduction = false
    init(manager: WindowManager, layout: RunningLayout, onApply: @escaping (WindowSetup, Set<String>) -> Void) {
        self.manager = manager; self.layout = layout; self.onApply = onApply
        var setup = layout.record.setup
        setup.count = min(40, layout.windows.count)
        _draft = State(initialValue: setup)
        _keeping = State(initialValue: Set(layout.record.windowIDs.prefix(setup.count)))
    }
    private var toClose: Int { layout.windows.count - keeping.count }
    private var valid: Bool { draft.isValid && keeping.count == min(draft.count, layout.windows.count) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Adjust this layout").font(.title2.bold())
                Text("\(layout.windows.count) open · \(layout.location)").font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Layout name", text: $draft.name).textFieldStyle(.roundedBorder)
                    Stepper("Windows: \(draft.count)", value: $draft.count, in: 1...40)
                    HStack {
                        Stepper("Columns: \(draft.columns == 0 ? "Auto" : String(draft.columns))", value: $draft.columns, in: 0...20)
                        Stepper("Rows: \(draft.rows == 0 ? "Auto" : String(draft.rows))", value: $draft.rows, in: 0...20)
                    }
                    HStack {
                        Text("Spacing: \(Int(draft.gap)) pt").frame(width: 100, alignment: .leading)
                        Slider(value: $draft.gap, in: 0...32, step: 1)
                    }
                    Toggle("Keep full-screen windows in full screen", isOn: Binding(get: { draft.keepsFullScreen }, set: { draft.preserveFullScreen = $0 }))
                    GridPreview(count: draft.count, columns: draft.columns, rows: draft.rows, gap: draft.gap,
                        displayBounds: Display.all.first { $0.id == draft.displayID }?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080))
                        .frame(height: 90).background(TilezStyle.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    Divider()
                    Text("Windows to keep · \(keeping.count) selected").font(.headline)
                    Text(draft.count < layout.windows.count ? "Uncheck windows to close and select the ones you want to keep. Choose exactly \(draft.count)." : "Existing members stay in this set. Increasing the count opens new windows without borrowing from another layout.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(layout.windows) { window in
                        TilezWindowRow(window: window, selected: Binding(get: { keeping.contains(window.id) }, set: { keep in
                            if keep { keeping.insert(window.id) } else { keeping.remove(window.id) }
                        })).disabled(draft.count >= layout.windows.count)
                    }
                }.padding(2)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text(toClose > 0 ? "Closes \(toClose) · keeps \(keeping.count)" : draft.count > layout.windows.count ? "Opens \(draft.count - layout.windows.count) new windows" : "Rearranges this set")
                    .font(.caption).foregroundStyle(.secondary)
                Button(toClose > 0 ? "Review changes…" : "Apply changes") {
                    if toClose > 0 { confirmReduction = true } else { onApply(draft, keeping) }
                }.buttonStyle(TilezButtonStyle(role: .primary)).disabled(!valid || manager.openingPID != nil)
            }
        }.padding(24).frame(width: 570, height: 690)
            .buttonStyle(TilezButtonStyle()).tint(TilezStyle.accent)
            .onChange(of: draft.count) { _, count in keeping = Set(layout.record.windowIDs.prefix(count)) }
            .alert("Close \(toClose) windows and rearrange?", isPresented: $confirmReduction) {
                Button("Cancel", role: .cancel) {}
                Button("Close \(toClose) and apply", role: .destructive) { onApply(draft, keeping) }
            } message: {
                Text("The unchecked windows will close. Tilez cannot undo closing windows, and will stop if an app asks to save. Your other layouts stay open.")
            }
    }
}
