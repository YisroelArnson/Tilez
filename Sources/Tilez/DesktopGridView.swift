import AppKit
import SwiftUI
import TilezCore

// Light control surfaces use black; desktop selections use white for contrast.
private let gridAccent = Color.black

struct GridGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// The overlay's pointer, polled by `PointerTracker` in the `gridRootSpace` coordinate space.
/// SwiftUI's own hover never fires in the overlay panel, so controls read this instead.
private struct GridPointerKey: EnvironmentKey { static let defaultValue: CGPoint? = nil }
private extension EnvironmentValues {
    var gridPointer: CGPoint? {
        get { self[GridPointerKey.self] }
        set { self[GridPointerKey.self] = newValue }
    }
}
private let gridRootSpace = "gridRoot"

/// Renders `content(hovered)` in the space it is given, e.g. as a control's background.
private struct PointerHover<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @Environment(\.gridPointer) private var pointer
    var body: some View {
        GeometryReader { proxy in
            content(pointer.map { proxy.frame(in: .named(gridRootSpace)).contains($0) } ?? false)
        }
    }
}

private struct GridButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .padding(.horizontal, 12).frame(minHeight: 34)
            .background {
                PointerHover { hovered in
                    let hovered = hovered && enabled
                    RoundedRectangle(cornerRadius: 10).fill(primary
                        ? gridAccent.opacity(configuration.isPressed ? 0.7 : hovered ? 0.8 : 1)
                        : Color.white.opacity(configuration.isPressed ? 0.95 : hovered ? 0.8 : 0.4))
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(primary ? Color.clear : Color.white.opacity(0.6)))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion && NSEvent.pressedMouseButtons != 0 ? 0.96 : 1)
    }
}

/// Half of a split button. The container draws the resting fill; each half adds hover and
/// press on top so the whole control matches `GridButtonStyle` (40% → 80% → 95% white).
private struct SplitHalfStyle: ButtonStyle {
    var horizontalPadding: CGFloat = 12
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, horizontalPadding).frame(minHeight: 34)
            .background {
                PointerHover { hovered in
                    Rectangle().fill(Color.white.opacity(configuration.isPressed ? 0.92 : hovered && enabled ? 0.67 : 0))
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

struct DesktopGridView: View {
    @ObservedObject var model: GridEditorModel
    @State private var dragSource: Int?
    @State private var dragTarget: Int?
    @State private var dragTranslation = CGSize.zero
    @State private var repeatDrag = false
    @State private var suppressCellClick = false
    @State private var hoveredCell: Int?
    @State private var overDivider = false
    @State private var pointer: CGPoint?
    @State private var activeDivider: PaneDivider?
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            // Controls stay at native point sizes; only the grid grows with the desktop.
            let canvas = proxy.size
            let top = max(20, min(48, canvas.height * 0.055))
            let gridTop = top + 100
            let availableHeight = max(160, canvas.height - gridTop - 94)
            let aspect = (model.display?.bounds.width ?? canvas.width) / max(1, model.display?.bounds.height ?? canvas.height)
            let width = min(max(320, canvas.width * 0.90), availableHeight * aspect)
            let gridHeight = width / aspect
            ZStack(alignment: .top) {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { if model.choosingApp { model.choosingApp = false } else { model.dismissLayer() } }
                VStack(spacing: 0) {
                    toolbar
                    Text(toolbarHint)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .padding(.top, 10)
                }
                .padding(.top, top).zIndex(2)
                gridCanvas(width: width, height: gridHeight)
                    .frame(width: width, height: gridHeight)
                    .padding(.top, gridTop).zIndex(1)
                VStack {
                    Spacer()
                    footer
                }.padding(.bottom, 20).padding(.horizontal, 24).zIndex(3)
            }
            .frame(width: canvas.width, height: canvas.height)
            .coordinateSpace(name: gridRootSpace)
            .background(PointerTracker { pointer = $0 })
            .environment(\.gridPointer, pointer)
            .onChange(of: pointer) { _, point in
                // The grid is centered horizontally below the toolbar.
                let origin = CGPoint(x: (canvas.width - width) / 2, y: gridTop)
                pointerMoved(point.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) },
                             frames: model.grid.frames(in: CGRect(x: 0, y: 0, width: width, height: gridHeight)),
                             width: width, height: gridHeight)
            }
        }
        .tint(gridAccent)
        .preferredColorScheme(.light)
        .onChange(of: model.saving) { _, showing in nameFocused = showing }
        .onChange(of: model.hasActiveLayer) { _, active in
            if !active {
                nameFocused = false
                model.onFocusGrid?()
            }
        }
        .onExitCommand { model.dismissLayer() }
    }

    private var toolbarHint: String {
        if model.busy { return "Applying your layout…" }
        if model.resizing {
            let dropped = model.grid.slots.count - model.draftColumns * model.draftRows
            let warning = dropped > 0 ? "  ·  Removes \(dropped) pane\(dropped == 1 ? "" : "s"); windows stay open" : ""
            return "\(model.draftColumns) × \(model.draftRows)\(warning)  ·  Click or press ↵ to confirm  ·  Esc to cancel"
        }
        return "Double-click a pane to choose its app  ·  Add or merge at an edge  ·  Drag a divider to resize, double-click to reset  ·  Drag panes to swap"
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .padding(.horizontal, 24)
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            // G turns the layout preview into a size picker in place; both share one footprint.
            ZStack {
                if model.resizing {
                    GridSizePicker(columns: model.draftColumns, rows: model.draftRows,
                                   hover: { c, r in model.draftColumns = c; model.draftRows = r },
                                   select: model.resize(columns:rows:))
                } else {
                    Button(action: model.beginResize) {
                        GridLayoutPreview(grid: model.grid, selectedCell: model.selectedCell)
                            .overlay {
                                PointerHover { hovered in
                                    RoundedRectangle(cornerRadius: 9).strokeBorder(Color.black.opacity(hovered && !model.busy ? 0.25 : 0))
                                }
                            }
                    }.buttonStyle(.plain).help("Grid size (G)").disabled(model.busy)
                        .accessibilityLabel("Current layout, \(model.grid.slots.count) panes. Choose grid size")
                }
            }.animation(.easeOut(duration: 0.12), value: model.resizing)
            Rectangle().fill(.black.opacity(0.10)).frame(width: 1, height: 28)
            Button(action: model.addApp) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                    Text(compact ? "Add" : "Add pane")
                    if !compact { keycap("⌘K") }
                }
            }.help("Add app (⌘K)").disabled(model.busy)
            // One control: save on the left, saved grids from the chevron.
            HStack(spacing: 0) {
                Button(action: model.beginSave) { Label("Save", systemImage: "bookmark") }
                    .buttonStyle(SplitHalfStyle())
                    .help("Save grid (⌘S)")
                    .disabled(model.grid.filledCount == 0 || model.busy)
                    .popover(isPresented: $model.saving, arrowEdge: .bottom) { savePopover }
                Rectangle().fill(.black.opacity(0.10)).frame(width: 1, height: 18)
                Button(action: model.beginSaved) {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                        .accessibilityLabel("Saved grids")
                }
                .buttonStyle(SplitHalfStyle(horizontalPadding: 9))
                .help("Saved grids (⌘O)").disabled(model.busy)
                .popover(isPresented: $model.showingSaved, arrowEdge: .bottom) { savedPopover }
            }
            .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.6)))
            if model.busy {
                Button("Stop", action: model.cancel)
            } else {
                Button(action: model.openGrid) {
                    HStack(spacing: 12) {
                        Text("Apply")
                        Image(systemName: "return")
                    }
                }.buttonStyle(GridButtonStyle(primary: true))
                    .disabled((model.grid.filledCount == 0 && model.originalGrid.filledCount == 0) || model.desktop == nil)
            }
            Menu {
                Button("Close all panes on Apply (⌘⇧⌫)", role: .destructive, action: model.removeAllPanes)
                Button("New empty grid (⌘N)", action: model.newGrid)
                Button("Undo grid edit (⌘Z)", action: model.undo)
                Button("Undo last window arrangement") { model.manager.undo() }
                    .disabled(model.manager.undoLabel == nil)
                Divider()
                Text("Show or hide Tilez: ⌃⌥Space")
                Text("Enlarge a window, or put it back: ⌃⌥Return or ⌃⌥-click")
                Button("Close", action: { model.onDismiss?() })
                Button("Quit Tilez") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 16) }
                .menuStyle(.borderlessButton).fixedSize().help("More actions")
                .padding(.horizontal, 8).frame(minHeight: 34)
                .background {
                    PointerHover { hovered in
                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovered && !model.busy ? 0.8 : 0))
                    }
                }
                .disabled(model.busy)
        }
        .buttonStyle(GridButtonStyle())
        .padding(10)
        .background {
            GridGlass(material: .popover)
                .overlay(Color.white.opacity(reduceTransparency ? 1 : 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.8)))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func gridCanvas(width: CGFloat, height: CGFloat) -> some View {
        let frames = model.grid.frames(in: CGRect(x: 0, y: 0, width: width, height: height))
        return ZStack(alignment: .topLeading) {
            ForEach(model.grid.slots.indices, id: \.self) { index in
                let frame = frames[index]
                cell(index, compact: frame.height < 170 || frame.width < 220)
                    .frame(width: frame.width, height: frame.height)
                    .overlay {
                        if !model.busy && (hoveredCell == index || model.selectedCell == index) {
                            edgeButtons(index)
                        }
                    }
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(dragSource == index ? 0.45 : 1)
                    .zIndex(model.selectedCell == index ? Double(frames.count + 1) : Double(frames.count - index))
                    .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("grid"))
                        .onChanged { value in
                            guard !model.busy, model.grid.slots[index].app != nil else { return }
                            if dragSource == nil {
                                dragSource = index; suppressCellClick = true
                                model.closeLayers()
                            }
                            dragTranslation = value.translation
                            dragTarget = frames.indices.first { $0 != index && frames[$0].contains(value.location) }
                            repeatDrag = NSEvent.modifierFlags.contains(.shift)
                        }
                        .onEnded { _ in
                            if let source = dragSource, let target = dragTarget { model.move(from: source, to: target, repeating: repeatDrag) }
                            dragSource = nil; dragTarget = nil; dragTranslation = .zero
                            DispatchQueue.main.async { suppressCellClick = false }
                        })
            }
            ForEach(model.grid.dividers) { divider in
                dividerHandle(divider, width: width, height: height).zIndex(Double(frames.count + 2))
            }
            if let source = dragSource, model.grid.slots.indices.contains(source), let app = model.grid.slots[source].app {
                HStack(spacing: 10) {
                    Image(nsImage: model.icon(for: app)).resizable().frame(width: 36, height: 36)
                    Text(app.name).font(.system(size: 15, weight: .medium))
                    if repeatDrag { Image(systemName: "plus.circle.fill").foregroundStyle(gridAccent) }
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12, y: 5)
                    .position(x: frames[source].midX + dragTranslation.width, y: frames[source].midY + dragTranslation.height)
                    .allowsHitTesting(false).zIndex(1000)
            }
        }.frame(width: width, height: height, alignment: .topLeading).coordinateSpace(name: "grid")
    }

    /// Hover comes from polling the pointer: SwiftUI's hover never reached the panes in this panel.
    private func pointerMoved(_ point: CGPoint?, frames: [CGRect], width: CGFloat, height: CGFloat) {
        var cell: Int?
        var divider: PaneDivider?
        if let point, dragSource == nil {
            divider = activeDivider ?? model.grid.dividers.first { dividerRect($0, width: width, height: height).contains(point) }
            if let selected = model.selectedCell, frames.indices.contains(selected), frames[selected].contains(point) { cell = selected }
            else { cell = frames.indices.first { frames[$0].contains(point) } }
        }
        if cell != hoveredCell { hoveredCell = cell }
        if let divider { (divider.vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() }
        else if overDivider { NSCursor.arrow.set() }
        overDivider = divider != nil
    }

    private func dividerRect(_ divider: PaneDivider, width: CGFloat, height: CGFloat) -> CGRect {
        let length = (divider.upper - divider.lower) * (divider.vertical ? height : width)
        let x = (divider.vertical ? divider.position : (divider.lower + divider.upper) / 2) * width
        let y = (divider.vertical ? (divider.lower + divider.upper) / 2 : divider.position) * height
        return divider.vertical ? CGRect(x: x - 7, y: y - length / 2, width: 14, height: length)
                                : CGRect(x: x - length / 2, y: y - 7, width: length, height: 14)
    }

    private func dividerHandle(_ divider: PaneDivider, width: CGFloat, height: CGFloat) -> some View {
        let length = (divider.upper - divider.lower) * (divider.vertical ? height : width)
        let handleWidth: CGFloat = divider.vertical ? 14 : length
        let handleHeight: CGFloat = divider.vertical ? length : 14
        let x = (divider.vertical ? divider.position : (divider.lower + divider.upper) / 2) * width
        let y = (divider.vertical ? (divider.lower + divider.upper) / 2 : divider.position) * height
        return RoundedRectangle(cornerRadius: 3)
            .fill(activeDivider?.id == divider.id ? Color.white : Color.white.opacity(0.65))
            .shadow(color: .black.opacity(0.65), radius: activeDivider?.id == divider.id ? 2 : 0)
            .frame(width: divider.vertical ? 3 : max(16, length - 28), height: divider.vertical ? max(16, length - 28) : 3)
            .frame(width: handleWidth, height: handleHeight)
            .contentShape(Rectangle()).position(x: x, y: y)
            // A small threshold keeps a double-click from nudging the divider first.
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("grid"))
                .onChanged { value in
                    if activeDivider == nil { activeDivider = divider }
                    guard let active = activeDivider else { return }
                    let offset = active.vertical ? value.translation.width / width : value.translation.height / height
                    model.previewDivider(active, position: active.position + offset)
                }
                .onEnded { _ in model.finishDivider(); activeDivider = nil })
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetDivider(divider) })
            .help("Drag to resize · Double-click to reset")
            .accessibilityLabel("Resize divider between panes \(divider.before + 1) and \(divider.after + 1)")
            .accessibilityAdjustableAction { direction in
                model.previewDivider(divider, position: divider.position + (direction == .increment ? 0.025 : -0.025))
                model.finishDivider()
            }
            .accessibilityAction(named: "Reset") { model.resetDivider(divider) }
            .allowsHitTesting(!model.busy)
    }

    /// Each edge offers + to split and, when the neighbors line up, a merge that grows
    /// this pane over them. The pane whose button you click is the one that stays.
    private func edgeButtons(_ index: Int) -> some View {
        GeometryReader { proxy in
            ForEach(PaneEdge.allCases, id: \.self) { edge in
                let point = CGPoint(x: edge == .left ? 18 : edge == .right ? proxy.size.width - 18 : proxy.size.width / 2,
                                    y: edge == .top ? 18 : edge == .bottom ? proxy.size.height - 18 : proxy.size.height / 2)
                edgeButton("plus") { model.split(index, toward: edge) }
                    .position(point)
                    .help("Add a pane to the \(edge.rawValue)")
                    .accessibilityLabel("Add pane \(edge.rawValue) of pane \(index + 1)")
                if !model.grid.mergeCandidates(index, toward: edge).isEmpty {
                    let along = edge == .top || edge == .bottom
                    edgeButton("arrow.\(edge == .top ? "up" : edge == .bottom ? "down" : edge.rawValue).to.line") {
                        model.merge(index, toward: edge)
                    }
                    .position(x: point.x + (along ? 34 : 0), y: point.y + (along ? 0 : 34))
                    .help("Merge with the pane \(mergePhrase(edge))\(model.grid.slots[index].app.map { ", keeping \($0.name)" } ?? "")")
                    .accessibilityLabel("Merge pane \(index + 1) with the pane \(mergePhrase(edge))")
                }
            }
        }
    }

    private func edgeButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gridAccent).frame(width: 24, height: 24)
                .background(.white, in: Circle()).shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(.plain)
    }

    private func mergePhrase(_ edge: PaneEdge) -> String {
        edge == .top ? "above" : edge == .bottom ? "below" : "to the \(edge.rawValue)"
    }

    private var canClickCell: Bool { dragSource == nil && !suppressCellClick && !model.busy }

    private func cell(_ index: Int, compact: Bool) -> some View {
        let app = model.grid.slots[index].app
        let selected = model.selectedCell == index || dragTarget == index
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                // A dark tint keeps white icons and labels legible over light windows.
                .fill(reduceTransparency ? Color(white: 0.25) : Color.black.opacity(hoveredCell == index ? 0.55 : 0.45))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? Color.white : .white.opacity(0.45), lineWidth: selected ? 3 : 1)
                .shadow(color: .black.opacity(selected ? 0.75 : 0), radius: 2)
            // Clicking a pane only selects it; double-click or its center opens the chooser.
            Color.clear.contentShape(Rectangle())
                .gesture(TapGesture(count: 2).onEnded { if canClickCell { model.choose(index) } })
                .simultaneousGesture(TapGesture().onEnded { if canClickCell { model.select(index) } })
                .accessibilityElement()
                .accessibilityLabel("Pane \(index + 1), \(app?.name ?? "empty")")
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
                .accessibilityAction { model.select(index) }
            Button { if canClickCell { model.choose(index) } } label: {
                VStack(spacing: compact ? 8 : 10) {
                    if let app {
                        Image(nsImage: model.icon(for: app)).resizable().interpolation(.high)
                            .frame(width: compact ? 32 : 48, height: compact ? 32 : 48)
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                        Text(app.name).font(.system(size: compact ? 13 : 14, weight: .medium)).lineLimit(1)
                        if !compact, let title = model.grid.slots[index].title, !title.isEmpty {
                            Text(title).font(.system(size: 11)).lineLimit(1).opacity(0.8)
                        }
                    } else {
                        Image(systemName: "plus").font(.system(size: compact ? 18 : 22, weight: .light))
                            .frame(width: compact ? 30 : 38, height: compact ? 30 : 38)
                            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1.5))
                        Text("Choose an app").font(.system(size: compact ? 12 : 13, weight: .medium))
                    }
                }.foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(PaneAppButtonStyle(highlighted: hoveredCell == index)).disabled(model.busy)
                .frame(maxWidth: max(0, (compact ? 180 : 320)))
                .padding(.horizontal, 28)
                .help(app == nil ? "Choose an app" : "Change app")
                .accessibilityLabel("Pane \(index + 1), \(app?.name ?? "empty"). Choose app")
                .popover(isPresented: Binding(get: { model.choosingApp && model.selectedCell == index },
                                              set: { if !$0 { model.choosingApp = false } }), arrowEdge: .trailing) {
                    appPopover(index)
                }
            VStack {
                HStack {
                    Text("\(index + 1)").font(.system(size: 12, weight: .medium)).opacity(0.8)
                    Spacer()
                }
                Spacer()
            }.foregroundStyle(.white).padding(12).allowsHitTesting(false)
        }
        .contextMenu {
            Button("Choose app…") { model.choose(index) }
            ForEach(PaneEdge.allCases, id: \.self) { edge in
                Button("Add pane \(edge.rawValue)") { model.split(index, toward: edge) }
            }
            let mergeable = PaneEdge.allCases.filter { !model.grid.mergeCandidates(index, toward: $0).isEmpty }
            if !mergeable.isEmpty {
                Divider()
                ForEach(mergeable, id: \.self) { edge in
                    Button("Merge with the pane \(mergePhrase(edge))") {
                        model.merge(index, toward: edge)
                    }
                }
            }
            if app != nil {
                Button("Repeat in empty cells") {
                    model.repeatInEmptyCells(index)
                }
                Button("Remove pane", role: .destructive) { model.removePane(index) }
                    .help("Closes this window when you apply the layout")
            }
        }
    }

    private func appPopover(_ index: Int) -> some View {
        let currentApp = model.grid.slots.indices.contains(index) ? model.grid.slots[index].app : nil
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                GridSearchField(placeholder: "Search apps…", text: $model.search, onSubmit: model.confirmSearchSelection)
                    .frame(height: 20)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.padding(10).background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredApps) { choice in
                            Button { model.assign(choice.app) } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: model.icon(for: choice.app)).resizable().frame(width: 30, height: 30)
                                    Text(choice.app.name).font(.system(size: 14)).lineLimit(1)
                                    Spacer()
                                    if currentApp == choice.app { Image(systemName: "checkmark").foregroundStyle(gridAccent) }
                                }.padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(AppRowStyle(selected: model.selectedAppChoice?.id == choice.id))
                                .id(choice.id)
                                .accessibilityAddTraits(model.selectedAppChoice?.id == choice.id ? [.isSelected] : [])
                        }
                        if model.filteredApps.isEmpty {
                            if model.loadingApps { ProgressView("Loading apps…").padding(20) }
                            else { Text("No apps found").foregroundStyle(.secondary).padding(20) }
                        }
                    }
                }.frame(height: min(280, CGFloat(max(1, model.filteredApps.count)) * 47))
                .onChange(of: model.selectedAppChoice?.id) { _, id in
                    if let id { reader.scrollTo(id) }
                }
            }
            searchHints
            if currentApp != nil {
                Divider()
                Button("Remove pane", role: .destructive) { model.removePane(index) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    .help("Closes this window when you apply the layout")
            }
        }.padding(12).frame(width: 280).preferredColorScheme(.light)
            .environment(\.gridPointer, nil)
            .onDisappear { model.onFocusGrid?() }
    }

    private var savePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save this grid").font(.system(size: 15, weight: .semibold))
            TextField("Name", text: $model.saveName).textFieldStyle(.roundedBorder)
                .focused($nameFocused).onSubmit { model.save() }
            Text("Use it on any screen or desktop.").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Save", action: model.save).buttonStyle(GridButtonStyle(primary: true))
                .disabled(model.saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(18).frame(width: 280).preferredColorScheme(.light).onAppear { nameFocused = true }
            .environment(\.gridPointer, nil)
    }

    private var savedPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved grids").font(.system(size: 15, weight: .semibold))
            GridSearchField(placeholder: "Search saved grids…", text: $model.savedSearch, onSubmit: model.confirmSearchSelection)
                .frame(height: 20).padding(10)
                .background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.filteredSaved) { item in
                            HStack {
                                Button { model.load(item) } label: {
                                    HStack {
                                        Image(systemName: "square.grid.2x2").foregroundStyle(gridAccent)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name).lineLimit(1)
                                            Text("\(item.grid.columns) × \(item.grid.rows) · \(item.grid.filledCount) apps")
                                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }.padding(8).contentShape(Rectangle())
                                }.buttonStyle(AppRowStyle(selected: model.selectedSavedGrid?.id == item.id))
                                    .accessibilityAddTraits(model.selectedSavedGrid?.id == item.id ? [.isSelected] : [])
                                Button { model.deleteSaved(item.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete saved grid")
                            }.id(item.id)
                        }
                        if model.filteredSaved.isEmpty {
                            Text(model.saved.isEmpty ? "Save a grid with ⌘S to reuse it here." : "No matching grids")
                                .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 16)
                        }
                    }
                }.frame(maxHeight: 270)
                .onChange(of: model.selectedSavedGrid?.id) { _, id in
                    if let id { reader.scrollTo(id) }
                }
            }
            searchHints
        }.padding(16).frame(width: 310).preferredColorScheme(.light)
            .environment(\.gridPointer, nil)
            .onDisappear { model.onFocusGrid?() }
    }

    private var searchHints: some View {
        Text("↑ ↓ Select   ↵ Confirm   Esc Back")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if model.desktop?.isFullScreen == true && model.grid != model.originalGrid {
                Text("Apply will leave full screen to arrange these panes on this display.")
                    .font(.system(size: 12)).foregroundStyle(.white)
            }
            if model.grid.windowsToClose?.isEmpty == false {
                Text("Removed and replaced windows will close on Apply.")
                    .font(.system(size: 12)).foregroundStyle(.white)
            }
            if !model.trusted {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised")
                    Text("Allow Accessibility so Tilez can arrange your windows.")
                    Button("Allow access") {
                        Accessibility.requestPermission()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }.buttonStyle(GridButtonStyle(primary: true))
                }.font(.system(size: 13)).padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else if !model.message.isEmpty {
                HStack(spacing: 10) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.isError ? "exclamationmark.circle" : "checkmark.circle") }
                    Text(model.message).font(.system(size: 13)).lineLimit(3)
                }.padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            Text(keyboardHints)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        }
    }

    private var keyboardHints: String {
        if model.busy { return "Esc  Stop opening windows" }
        if model.choosingApp || model.showingSaved { return "↑ ↓  Select result   ·   ↵  Confirm   ·   Esc  Back to grid" }
        if model.saving { return "↵  Save grid   ·   Esc  Back to grid" }
        if model.resizing { return "Hover or ← → ↑ ↓  Choose size   ·   ↵  Confirm   ·   Esc  Cancel" }
        return "Arrows  Select   ·   ⌥Arrows  Split   ·   ⌥⇧Arrows  Merge   ·   ⌘⇧⌫  Close all   ·   Type / Space  Choose app   ·   G  Size   ·   ⌘S  Save   ·   ⌘O  Load   ·   ↵  Apply   ·   Esc  Close"
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.14)))
    }
}

/// The pane's app icon and name: highlights on hover so it reads as the chooser's target.
private struct PaneAppButtonStyle: ButtonStyle {
    var highlighted: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.28 : highlighted ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Reports the pointer in top-left coordinates. Polls while the panel is on screen
/// because hover events never reached the panes in this panel; it pauses when hidden.
/// It never takes clicks; SwiftUI views above it keep handling them.
private struct PointerTracker: NSViewRepresentable {
    var moved: (CGPoint?) -> Void
    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView(); view.moved = moved; return view
    }
    func updateNSView(_ view: TrackingView, context: Context) { view.moved = moved }

    final class TrackingView: NSView {
        var moved: ((CGPoint?) -> Void)?
        private var timer: Timer?
        private var observers: [NSObjectProtocol] = []
        private var last: CGPoint?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification].compactMap { name in
                window.map { window in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.updateTimer() }
                    }
                }
            }
            updateTimer()
        }

        private func updateTimer() {
            let visible = window?.isVisible == true && (window?.isKeyWindow == true || window?.occlusionState.contains(.visible) == true)
            if visible, timer == nil {
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.poll() }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            } else if !visible {
                timer?.invalidate(); timer = nil
                if last != nil { last = nil; moved?(nil) }
            }
        }

        private func poll() {
            guard let window, window.isVisible else { updateTimer(); return }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let inside = bounds.contains(point) ? point : nil
            guard inside != last else { return }
            last = inside
            moved?(inside)
        }

        deinit {
            timer?.invalidate()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

private struct AppRowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { AppRowBody(configuration: configuration, selected: selected) }
    private struct AppRowBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label.foregroundStyle(.primary)
                .background(gridAccent.opacity(configuration.isPressed ? 0.22 : selected ? 0.14 : hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}

/// Uses the same geometry as the editor, including unequal and nested splits.
struct GridLayoutPreview: View {
    let grid: DesktopGrid
    let selectedCell: Int?

    var body: some View {
        GeometryReader { proxy in
            let frames = grid.frames(in: CGRect(origin: .zero, size: proxy.size), gap: 2)
            ZStack(alignment: .topLeading) {
                ForEach(grid.slots.indices.reversed(), id: \.self) { index in
                    let frame = frames[index]
                    // The selected pane is darker rather than outlined.
                    let selected = selectedCell == index
                    RoundedRectangle(cornerRadius: 2)
                        .fill(grid.slots[index].app == nil ? Color.black.opacity(selected ? 0.22 : 0.10)
                                                           : gridAccent.opacity(selected ? 0.85 : 0.55))
                        .overlay {
                            // A light inner edge keeps the margin between panes.
                            RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                        }
                        .frame(width: max(0, frame.width), height: max(0, frame.height))
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: 75, height: 49)
        .padding(5).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }
}

/// Hovering updates the draft so pointer and arrow keys edit the same size.
private struct GridSizePicker: View {
    let columns: Int
    let rows: Int
    let hover: (Int, Int) -> Void
    let select: (Int, Int) -> Void
    private let step: CGFloat = 13
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<DesktopGrid.maxRows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<DesktopGrid.maxColumns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(column < columns && row < rows ? gridAccent : Color.black.opacity(0.12))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .padding(5).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(gridAccent.opacity(0.5)))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let point) = phase {
                let size = dimensions(point)
                if size != (columns, rows) { hover(size.0, size.1) }
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in hover(dimensions(value.location).0, dimensions(value.location).1) }
            .onEnded { value in let size = dimensions(value.location); select(size.0, size.1) })
        .help("Choose a grid size · up to 6 columns and 4 rows")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grid size, \(columns) columns by \(rows) rows")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { hover(min(DesktopGrid.maxColumns, columns + 1), rows) }
            else if direction == .decrement { hover(max(1, columns - 1), rows) }
        }
        .accessibilityAction(named: "Add row") { hover(columns, min(DesktopGrid.maxRows, rows + 1)) }
        .accessibilityAction(named: "Remove row") { hover(columns, max(1, rows - 1)) }
        .accessibilityAction(named: "Confirm size") { select(columns, rows) }
    }
    private func dimensions(_ point: CGPoint) -> (Int, Int) {
        (max(1, min(DesktopGrid.maxColumns, Int(floor((point.x - 5) / step)) + 1)),
         max(1, min(DesktopGrid.maxRows, Int(floor((point.y - 5) / step)) + 1)))
    }
}
