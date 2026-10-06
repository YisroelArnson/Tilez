import AppKit
import SwiftUI
import TilezCore

// Light control surfaces use black; desktop selections use white for contrast.
private let gridAccent = Color.black

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

struct GridButtonStyle: ButtonStyle {
    var primary = false
    /// Capsule-shaped, for buttons inside a pill.
    var capsule = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? Metrics.control / 2 : Metrics.controlRadius)
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .padding(.horizontal, Space.md).frame(minHeight: Metrics.control)
            .background {
                PointerHover { hovered in
                    let hovered = hovered && enabled
                    shape.fill(primary
                        ? gridAccent.opacity(configuration.isPressed ? 0.7 : hovered ? 0.8 : 1)
                        : Color.white.opacity(configuration.isPressed ? 0.95 : hovered ? 0.8 : 0.45))
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion && NSEvent.pressedMouseButtons != 0 ? 0.96 : 1)
    }
}

/// A control that rests clear and fills on hover, for icon buttons and workspace chips.
/// `selected` keeps the fill, marking the workspace this screen shows.
private struct QuietButtonStyle: ButtonStyle {
    var selected = false
    var leading: CGFloat = Space.sm
    var trailing: CGFloat = Space.sm
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.leading, leading).padding(.trailing, trailing)
            .frame(minWidth: Metrics.control, minHeight: Metrics.control)
            .background {
                PointerHover { hovered in
                    RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(Color.white.opacity(
                        configuration.isPressed ? 0.95 : selected ? 0.85 : hovered && enabled ? 0.6 : 0))
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Half of a split button. The container draws the resting fill; each half adds hover and
/// press on top so the whole control matches `GridButtonStyle` (40% → 80% → 95% white).
private struct SplitHalfStyle: ButtonStyle {
    var horizontalPadding: CGFloat = Space.md
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, horizontalPadding).frame(minHeight: Metrics.control)
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
    @State private var activeResize: PaneResize?
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            // Controls stay at native point sizes; only the grid grows with the desktop.
            let canvas = proxy.size
            let top = max(Space.lg, min(Space.xxl + Space.lg, canvas.height * 0.04))
            let gridTop = top + Metrics.barHeight + Space.sm + Self.hintHeight + Space.lg
            let availableHeight = max(160, canvas.height - gridTop - Self.footerReserve)
            let aspect = (model.display?.bounds.width ?? canvas.width) / max(1, model.display?.bounds.height ?? canvas.height)
            let width = min(max(320, canvas.width * 0.90), availableHeight * aspect)
            let gridHeight = width / aspect
            ZStack(alignment: .top) {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { if model.choosingApp { model.choosingApp = false } else { model.dismissLayer() } }
                VStack(spacing: Space.sm) {
                    toolbar
                    Text(toolbarHint)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .lineLimit(1).frame(height: Self.hintHeight)
                }
                .padding(.top, top).zIndex(2)
                gridCanvas(width: width, height: gridHeight)
                    .frame(width: width, height: gridHeight)
                    .padding(.top, gridTop).zIndex(1)
                VStack {
                    Spacer()
                    footer
                }.padding(.bottom, Space.lg).padding(.horizontal, Space.xl).zIndex(3)
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

    private static let hintHeight: CGFloat = 16
    /// Room below the grid for a pill and the keyboard hints.
    private static let footerReserve: CGFloat = Space.xxl * 3

    private var toolbarHint: String {
        if model.busy { return "Applying your layout…" }
        if model.resizing {
            let dropped = model.grid.slots.count - model.draftColumns * model.draftRows
            let warning = dropped > 0 ? "  ·  Removes \(dropped) pane\(dropped == 1 ? "" : "s"); windows stay open" : ""
            return "\(model.draftColumns) × \(model.draftRows)\(warning)  ·  Click or press ↵ to confirm  ·  Esc to cancel"
        }
        if let workspace = model.shownWorkspace {
            return "Workspace “\(workspace.name)”" + (model.workspaceModified ? "  ·  Edited  ·  ⌘S saves it" : "")
                + "  ·  ⌘⇧S saves a new workspace"
        }
        return "Double-click a pane to choose its app  ·  Add or merge at an edge  ·  Drag an edge or corner to resize  ·  Drag panes to swap"
    }

    /// One bar: workspaces, then editing, then saving and applying. Narrow screens drop the
    /// workspace names first, then shorten labels, then leave workspaces to ⌘O.
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            bar(chips: .named, compact: false)
            bar(chips: .numbered, compact: false)
            bar(chips: .numbered, compact: true)
            bar(chips: .hidden, compact: true)
        }
        .padding(.horizontal, Space.xl)
    }

    private func bar(chips: WorkspaceChips.Labels, compact: Bool) -> some View {
        HStack(spacing: Space.xs) {
            if chips != .hidden, let store = model.workspaces {
                WorkspaceChips(store: store, model: model, labels: chips)
            }
            Button(action: model.beginResize) {
                GridLayoutPreview(grid: model.grid, selectedCell: model.selectedCell)
            }
            .buttonStyle(QuietButtonStyle(selected: model.resizing, leading: Space.xs, trailing: Space.xs))
            .help("Grid size (G)").disabled(model.busy)
            .accessibilityLabel("Current layout, \(model.grid.slots.count) panes. Choose grid size")
            .popover(isPresented: $model.resizing, arrowEdge: .bottom) { sizePopover }
            Button(action: model.addApp) { Label(compact ? "Add" : "Add pane", systemImage: "plus") }
                .buttonStyle(QuietButtonStyle(trailing: Space.md))
                .help("Add a pane (⌘K)").disabled(model.busy)
            BarSeparator().padding(.horizontal, Space.xs)
            // Save the workspace on the left; workspaces, layouts, and Save As from the chevron.
            HStack(spacing: 0) {
                saveButton
                openButton
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
            if model.busy {
                Button("Stop", action: model.cancel).buttonStyle(GridButtonStyle())
            } else {
                Button(action: model.openGrid) {
                    HStack(spacing: Space.sm) {
                        Text("Apply")
                        Image(systemName: "return")
                    }
                }.buttonStyle(GridButtonStyle(primary: true))
                    .disabled((model.grid.filledCount == 0 && model.originalGrid.filledCount == 0) || model.desktop == nil)
                    .padding(.leading, Space.xs)
            }
            moreMenu
        }
        .padding(Metrics.barPadding)
        .glassSurface(RoundedRectangle(cornerRadius: Metrics.barRadius), reduceTransparency: reduceTransparency)
        .fixedSize()
    }

    private var sizePopover: some View {
        VStack(spacing: Space.sm) {
            GridSizePicker(columns: model.draftColumns, rows: model.draftRows,
                           hover: { c, r in model.draftColumns = c; model.draftRows = r },
                           select: model.resize(columns:rows:))
            Text("\(model.draftColumns) × \(model.draftRows)")
                .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(Space.md).preferredColorScheme(.light)
        .environment(\.gridPointer, nil)
        .onDisappear { model.onFocusGrid?() }
    }

    private func gridCanvas(width: CGFloat, height: CGFloat) -> some View {
        let frames = model.grid.frames(in: CGRect(x: 0, y: 0, width: width, height: height))
        // While a swap drag hovers another pane, both are drawn where the swap would put them.
        // Hover still hit-tests the original frames, so returning to your own spot cancels it.
        func place(_ index: Int) -> Int {
            guard let source = dragSource, let target = dragTarget, !repeatDrag else { return index }
            return index == source ? target : index == target ? source : index
        }
        return ZStack(alignment: .topLeading) {
            ForEach(model.grid.slots.indices, id: \.self) { index in
                let frame = frames[place(index)]
                cell(index, compact: frame.height < 170 || frame.width < 220)
                    .frame(width: frame.width, height: frame.height)
                    .overlay {
                        if !model.busy && dragSource == nil && (hoveredCell == index || model.selectedCell == index) {
                            edgeButtons(index)
                        }
                    }
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(dragSource == index ? 0.45 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: dragTarget)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: repeatDrag)
                    .zIndex(model.selectedCell == index ? Double(frames.count + 1) : Double(frames.count - index))
                    .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("grid"))
                        .onChanged { value in
                            guard !model.busy else { return }
                            // A drag that starts on a side or corner resizes; anywhere else it swaps.
                            if activeResize == nil, dragSource == nil {
                                let edges = resizeEdges(index, at: value.startLocation, frames: frames)
                                if !edges.isEmpty { activeResize = PaneResize(index: index, edges: edges); suppressCellClick = true }
                            }
                            if let resize = activeResize {
                                model.previewResize(resize.index, edges: resize.edges,
                                                    by: CGSize(width: value.translation.width / width, height: value.translation.height / height))
                                return
                            }
                            guard model.grid.slots[index].app != nil else { return }
                            if dragSource == nil {
                                dragSource = index; suppressCellClick = true
                                model.closeLayers()
                            }
                            dragTranslation = value.translation
                            dragTarget = frames.indices.first { $0 != index && frames[$0].contains(value.location) }
                            repeatDrag = NSEvent.modifierFlags.contains(.shift)
                        }
                        .onEnded { _ in
                            if activeResize != nil {
                                model.finishDivider(); activeResize = nil
                                DispatchQueue.main.async { suppressCellClick = false }
                                return
                            }
                            // The preview already shows the swap, so the drop itself doesn't animate.
                            var instant = Transaction(); instant.disablesAnimations = true
                            withTransaction(instant) {
                                if let source = dragSource, let target = dragTarget { model.move(from: source, to: target, repeating: repeatDrag) }
                                dragSource = nil; dragTarget = nil; dragTranslation = .zero
                            }
                            DispatchQueue.main.async { suppressCellClick = false }
                        })
            }
            ForEach(model.grid.dividers) { divider in
                dividerHandle(divider, width: width, height: height).zIndex(Double(frames.count + 2))
            }
            if let source = dragSource, model.grid.slots.indices.contains(source), let app = model.grid.slots[source].app {
                HStack(spacing: Space.md) {
                    Image(nsImage: model.icon(for: app)).resizable().frame(width: 36, height: 36)
                    Text(app.name).font(.system(size: 15, weight: .medium))
                    if repeatDrag { Image(systemName: "plus.circle.fill").foregroundStyle(gridAccent) }
                }.padding(Space.md).background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.paneRadius + Space.xs))
                    .shadow(radius: 12, y: 5)
                    .position(x: frames[source].midX + dragTranslation.width, y: frames[source].midY + dragTranslation.height)
                    .allowsHitTesting(false).zIndex(1000)
            }
        }.frame(width: width, height: height, alignment: .topLeading).coordinateSpace(name: "grid")
    }

    /// Hover comes from polling the pointer: SwiftUI's hover never reached the panes in this panel.
    private func pointerMoved(_ point: CGPoint?, frames: [CGRect], width: CGFloat, height: CGFloat) {
        var cell: Int?
        var cursor: NSCursor?
        if let point, dragSource == nil {
            if let selected = model.selectedCell, frames.indices.contains(selected), frames[selected].contains(point) { cell = selected }
            else { cell = frames.indices.first { frames[$0].contains(point) } }
            if let resize = activeResize { cursor = resizeCursor(resize.edges) }
            else if let divider = activeDivider ?? model.grid.dividers.first(where: { dividerRect($0, width: width, height: height).contains(point) }) {
                cursor = divider.vertical ? .resizeLeftRight : .resizeUpDown
            } else if let cell, case let edges = resizeEdges(cell, at: point, frames: frames), !edges.isEmpty {
                cursor = resizeCursor(edges)
            }
        }
        if cell != hoveredCell { hoveredCell = cell }
        if let cursor { cursor.set() } else if overDivider { NSCursor.arrow.set() }
        overDivider = cursor != nil
    }

    /// The side or corner of a pane under `point`: a 10-point band along each side and an
    /// 18-point square at each corner, leaving out the edge buttons so they still click.
    private func resizeEdges(_ index: Int, at point: CGPoint, frames: [CGRect]) -> [PaneEdge] {
        guard frames.indices.contains(index), !model.busy else { return [] }
        let frame = frames[index]
        guard frame.contains(point) else { return [] }
        let horizontal: PaneEdge = point.x - frame.minX < frame.maxX - point.x ? .left : .right
        let vertical: PaneEdge = point.y - frame.minY < frame.maxY - point.y ? .top : .bottom
        let fromSide = min(point.x - frame.minX, frame.maxX - point.x)
        let fromTop = min(point.y - frame.minY, frame.maxY - point.y)
        if fromSide <= 18 && fromTop <= 18 { return [horizontal, vertical] }
        let edge: PaneEdge
        if fromSide <= 10 { edge = horizontal } else if fromTop <= 10 { edge = vertical } else { return [] }
        for side in PaneEdge.allCases {
            let button = CGPoint(x: side == .left ? frame.minX + 18 : side == .right ? frame.maxX - 18 : frame.midX,
                                 y: side == .top ? frame.minY + 18 : side == .bottom ? frame.maxY - 18 : frame.midY)
            let along = side == .top || side == .bottom
            let merge = CGPoint(x: button.x + (along ? 34 : 0), y: button.y + (along ? 0 : 34))
            if hypot(point.x - button.x, point.y - button.y) < 17 { return [] }
            if hypot(point.x - merge.x, point.y - merge.y) < 17, !model.grid.mergeCandidates(index, toward: side).isEmpty { return [] }
        }
        return [edge]
    }

    private func resizeCursor(_ edges: [PaneEdge]) -> NSCursor {
        guard edges.count == 2 else { return edges.first == .left || edges.first == .right ? .resizeLeftRight : .resizeUpDown }
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = edges.contains(.top)
                ? (edges.contains(.left) ? .topLeft : .topRight) : (edges.contains(.left) ? .bottomLeft : .bottomRight)
            return .frameResize(position: position, directions: .all)
        }
        return .crosshair
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
            RoundedRectangle(cornerRadius: Metrics.paneRadius)
                // A dark tint keeps white icons and labels legible over light windows.
                .fill(reduceTransparency ? Color(white: 0.25) : Color.black.opacity(hoveredCell == index ? 0.55 : 0.45))
            RoundedRectangle(cornerRadius: Metrics.paneRadius)
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
                VStack(spacing: compact ? Space.sm : Space.md) {
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
                    .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.controlRadius))
            }.buttonStyle(PaneAppButtonStyle(highlighted: hoveredCell == index)).disabled(model.busy)
                .frame(maxWidth: max(0, (compact ? 180 : 320)))
                .padding(.horizontal, Space.xl)
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
            }.foregroundStyle(.white).padding(Space.md).allowsHitTesting(false)
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
        return VStack(spacing: Space.sm) {
            SearchBox(placeholder: "Search apps…", text: $model.search, onSubmit: model.confirmSearchSelection)
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: Space.xxs) {
                        ForEach(model.filteredApps) { choice in
                            Button { model.assign(choice.app) } label: {
                                HStack(spacing: Space.md) {
                                    Image(nsImage: model.icon(for: choice.app)).resizable().frame(width: 24, height: 24)
                                    Text(choice.app.name).font(.system(size: 13)).lineLimit(1)
                                    Spacer()
                                    if currentApp == choice.app { Image(systemName: "checkmark").foregroundStyle(gridAccent) }
                                }.padding(.horizontal, Space.sm).frame(height: Self.rowHeight).contentShape(Rectangle())
                            }.buttonStyle(AppRowStyle(selected: model.selectedAppChoice?.id == choice.id))
                                .id(choice.id)
                                .accessibilityAddTraits(model.selectedAppChoice?.id == choice.id ? [.isSelected] : [])
                        }
                        if model.filteredApps.isEmpty {
                            if model.loadingApps { ProgressView("Loading apps…").padding(Space.lg) }
                            else { Text("No apps found").foregroundStyle(.secondary).padding(Space.lg) }
                        }
                    }
                }.frame(height: min(7 * (Self.rowHeight + Space.xxs), CGFloat(max(1, model.filteredApps.count)) * (Self.rowHeight + Space.xxs)))
                .onChange(of: model.selectedAppChoice?.id) { _, id in
                    if let id { reader.scrollTo(id) }
                }
            }
            if currentApp != nil {
                Divider()
                Button("Remove pane", role: .destructive) { model.removePane(index) }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.sm)
                    .help("Closes this window when you apply the layout")
            }
        }.padding(Space.md).frame(width: 280).preferredColorScheme(.light)
            .environment(\.gridPointer, nil)
            .onDisappear { model.onFocusGrid?() }
    }

    static let rowHeight: CGFloat = 36

    private var savePopover: some View {
        let workspace = model.saveKind == .workspace
        return VStack(alignment: .leading, spacing: Space.md) {
            Text(workspace ? "Save as a new workspace" : "Save as a layout").font(.system(size: 14, weight: .semibold))
            TextField("Name", text: $model.saveName).textFieldStyle(.roundedBorder)
                .focused($nameFocused).onSubmit { model.save() }
            if workspace && Display.all.count > 1 {
                Picker("Save", selection: $model.saveAllScreens) {
                    Text("This screen").tag(false)
                    Text("All screens").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
            Text(workspace ? "Keeps these exact windows. Closed windows leave it; nothing reopens."
                           : "Keeps the apps, not the windows. Opening it opens new windows on any screen or desktop.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Save", action: model.save).buttonStyle(GridButtonStyle(primary: true))
                .disabled(model.saveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(Space.lg).frame(width: 300).preferredColorScheme(.light).onAppear { nameFocused = true }
            .environment(\.gridPointer, nil)
    }

    private var moreMenu: some View {
        Menu {
            Button("Close all panes on Apply (⌘⇧⌫)", role: .destructive, action: model.removeAllPanes)
            Button("Realign panes (⌘R)", action: model.realign)
            Button("Tile all windows on this screen (⌘T)") { model.tileAll() }
            ForEach(model.otherScreens) { screen in
                Button("Bring \(windowCount(screen.windows.count)) from \(screen.name)") { model.bring(from: screen.id) }
            }
            Button("New empty grid (⌘N)", action: model.newGrid)
            Button("Undo grid edit (⌘Z)", action: model.undo)
            Button("Undo last window arrangement") { model.manager.undo() }
                .disabled(model.manager.undoLabel == nil)
            Divider()
            Text("Show or hide Tilez: ⌃⌥Space")
            Text("Enlarge a window, or put it back: ⌃⌥Return or ⌃⌥-click")
            Text("Quick add a tile: ⌃⌥N")
            Text("Realign windows: ⌃⌥R")
            Text("Open a workspace: ⌃⌥W, or ⌃⌥1–9")
            Text("Save the workspace: ⌃⌥S, or a new one: ⌃⌥⇧S")
            if Display.all.count > 1 || model.putBackAutomatically {
                Toggle("Put windows back automatically when a screen reconnects", isOn: $model.putBackAutomatically)
            }
            // A downloaded update holds Sparkle's session open until it installs, so checking again would do nothing.
            if model.updateReady, let version = model.availableUpdate, let update = model.onUpdate {
                Button("Restart to Install Tilez \(version)", action: update)
            } else if let check = model.onCheckForUpdates { Button("Check for Updates…", action: check) }
            Button("Close", action: { model.onDismiss?() })
            Button("Quit Tilez") { NSApp.terminate(nil) }
        } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More actions")
            .frame(width: Metrics.control, height: Metrics.control)
            .background {
                PointerHover { hovered in
                    RoundedRectangle(cornerRadius: Metrics.controlRadius).fill(Color.white.opacity(hovered && !model.busy ? 0.6 : 0))
                }
            }
            .disabled(model.busy)
    }

    private var openButton: some View {
        Button(action: model.beginSaved) {
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                .accessibilityLabel("Workspaces and layouts")
        }
        .buttonStyle(SplitHalfStyle(horizontalPadding: Space.sm))
        .help("Workspaces and layouts (⌘O)").disabled(model.busy)
        .popover(isPresented: $model.showingSaved, arrowEdge: .bottom) {
            SavedList(model: model).onDisappear { model.onFocusGrid?() }
        }
    }

    /// A dot marks a shown workspace with unsaved changes.
    private var saveButton: some View {
        let help: String = model.shownWorkspace.map { "Save workspace “\($0.name)” (⌘S)" } ?? "Save as a workspace (⌘S)"
        return Button(action: model.saveWorkspace) {
            HStack(spacing: Space.xs) {
                Label("Save", systemImage: "bookmark")
                if model.workspaceModified {
                    Circle().fill(Color.primary).frame(width: 6, height: 6).accessibilityLabel("Edited")
                }
            }
        }
        .buttonStyle(SplitHalfStyle())
        .help(help)
        .disabled(model.busy)
        .popover(isPresented: $model.saving, arrowEdge: .bottom) { savePopover }
    }

    private var footer: some View {
        VStack(spacing: Space.sm) {
            if let version = model.availableUpdate, let update = model.onUpdate {
                pill {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 16))
                    Text("Tilez \(version) is \(model.updateReady ? "ready" : "available")")
                    Button(model.updateReady ? "Restart" : "Update", action: update).buttonStyle(GridButtonStyle(primary: true, capsule: true))
                }
            }
            if !model.busy && !model.displaced.isEmpty {
                pill {
                    appIcons(model.displaced)
                    Text("\(windowCount(model.displaced.count)) from this screen \(model.displaced.count == 1 ? "is" : "are") on \(model.displacedLocation)")
                    Button("Put back", action: model.putBack).buttonStyle(GridButtonStyle(primary: true, capsule: true))
                }
            }
            if !model.busy && !model.hasActiveLayer && model.grid.hasOverlappingPanes {
                pill {
                    Image(systemName: "square.on.square").font(.system(size: 15))
                    Text("Some windows overlap")
                    Button(action: { model.tileAll() }) {
                        HStack(spacing: Space.sm) { Text("Tile all"); keycap("⌘T").colorScheme(.dark) }
                    }.buttonStyle(GridButtonStyle(primary: true, capsule: true))
                        .help("Arrange every window on this screen in an even grid. Apply moves them.")
                }
            }
            if model.desktop?.isFullScreen == true && model.grid != model.originalGrid {
                Text("Apply will leave full screen to arrange these panes on this display.")
                    .font(.system(size: 12)).foregroundStyle(.white)
            }
            if model.grid.windowsToClose?.isEmpty == false {
                Text("Removed and replaced windows will close on Apply.")
                    .font(.system(size: 12)).foregroundStyle(.white)
            }
            if !model.trusted {
                pill {
                    Image(systemName: "hand.raised")
                    Text("Allow Accessibility so Tilez can arrange your windows.")
                    Button("Allow access") {
                        Accessibility.requestPermission()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }.buttonStyle(GridButtonStyle(primary: true, capsule: true))
                }
            } else if !model.message.isEmpty {
                pill(trailing: Space.lg) {
                    if model.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.isError ? "exclamationmark.circle" : "checkmark.circle") }
                    Text(model.message).lineLimit(2)
                }
            }
            Text(keyboardHints)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        }
    }

    /// Notices share one look: an icon, a sentence, and at most one action, inset so a
    /// capsule button sits concentric with the pill.
    private func pill<Content: View>(trailing: CGFloat = Space.xs, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Space.md, content: content)
            .font(.system(size: 13, weight: .medium))
            .padding(.leading, Space.lg).padding(.trailing, trailing)
            .frame(minHeight: Metrics.pillHeight)
            .glassSurface(Capsule(), reduceTransparency: reduceTransparency)
            .preferredColorScheme(.light)
    }

    /// Up to four apps' icons, overlapping, for the windows a pill is about.
    private func appIcons(_ windows: [GridSlot]) -> some View {
        let apps = windows.compactMap(\.app).reduce(into: [GridApp]()) { apps, app in
            if !apps.contains(where: { $0.bundleID == app.bundleID }) { apps.append(app) }
        }
        return HStack(spacing: -Space.sm) {
            ForEach(apps.prefix(4), id: \.bundleID) { app in
                Image(nsImage: model.icon(for: app)).resizable().frame(width: 20, height: 20)
            }
        }.accessibilityHidden(true)
    }

    private func windowCount(_ count: Int) -> String { "\(count) window\(count == 1 ? "" : "s")" }

    private var keyboardHints: String {
        if model.busy { return "Esc  Stop opening windows" }
        if model.choosingApp || model.showingSaved { return "↑ ↓  Select result   ·   ↵  Confirm   ·   Esc  Back to grid" }
        if model.saving { return model.saveKind == .workspace ? "↵  Save workspace   ·   Esc  Back to grid" : "↵  Save layout   ·   Esc  Back to grid" }
        if model.resizing { return "Hover or ← → ↑ ↓  Choose size   ·   ↵  Confirm   ·   Esc  Cancel" }
        return "Arrows  Select   ·   ⌥Arrows  Split   ·   ⌥⇧Arrows  Merge   ·   ⌘R  Realign   ·   ⌘T  Tile all   ·   ⌘⇧⌫  Close all   ·   Type / Space  Choose app   ·   G  Size   ·   ⌘S  Save workspace   ·   ⌘O  Open   ·   ↵  Apply   ·   Esc  Close"
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, Space.xs + Space.xxs).padding(.vertical, Space.xxs)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Space.xs))
    }
}

/// The pane's app icon and name: highlights on hover so it reads as the chooser's target.
private struct PaneAppButtonStyle: ButtonStyle {
    var highlighted: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.28 : highlighted ? 0.14 : 0), in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
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
                .background(gridAccent.opacity(configuration.isPressed ? 0.22 : selected ? 0.12 : hovered ? 0.06 : 0), in: RoundedRectangle(cornerRadius: Metrics.rowRadius))
                .onHover { hovered = $0 }
        }
    }
}

/// Uses the same geometry as the editor, including unequal and nested splits. It fits inside a
/// control, inset by `Space.xs`.
struct GridLayoutPreview: View {
    let grid: DesktopGrid
    let selectedCell: Int?
    static let size = CGSize(width: 38, height: Metrics.control - Space.xs * 2)

    var body: some View {
        let frames = grid.frames(in: CGRect(origin: .zero, size: Self.size), gap: 1.5)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Metrics.insetRadius).fill(Color.white.opacity(0.6))
            ForEach(grid.slots.indices.reversed(), id: \.self) { index in
                let frame = frames[index]
                // The selected pane is darker rather than outlined.
                let selected = selectedCell == index
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(grid.slots[index].app == nil ? Color.black.opacity(selected ? 0.2 : 0.08)
                                                       : gridAccent.opacity(selected ? 0.8 : 0.45))
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

/// Hovering updates the draft so pointer and arrow keys edit the same size.
private struct GridSizePicker: View {
    let columns: Int
    let rows: Int
    let hover: (Int, Int) -> Void
    let select: (Int, Int) -> Void
    private static let cell: CGFloat = 16
    private let step: CGFloat = cell + Space.xs
    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(0..<DesktopGrid.maxRows, id: \.self) { row in
                HStack(spacing: Space.xs) {
                    ForEach(0..<DesktopGrid.maxColumns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: Space.xs)
                            .fill(column < columns && row < rows ? gridAccent : Color.black.opacity(0.1))
                            .frame(width: Self.cell, height: Self.cell)
                    }
                }
            }
        }
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

/// A pane side or corner being dragged; corners carry one horizontal and one vertical edge.
private struct PaneResize: Equatable {
    let index: Int
    let edges: [PaneEdge]
}

/// The first nine workspaces, numbered for ⌃⌥1–9. Click one to open it; the one this screen
/// shows is outlined. Right-click to rename, reorder, or delete.
/// The first nine workspaces at the start of the bar, each its thumbnail and number, with its
/// name when there's room. The one this screen shows stays filled.
struct WorkspaceChips: View {
    enum Labels { case named, numbered, hidden }
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var model: GridEditorModel
    let labels: Labels

    var body: some View {
        let shown = store.workspaces.prefix(9)
        if !shown.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, workspace in
                    chip(workspace, number: index + 1)
                }
                if store.workspaces.count > 9 {
                    Button(action: model.beginSaved) { Image(systemName: "ellipsis") }
                        .buttonStyle(QuietButtonStyle()).help("All workspaces (⌘O)")
                }
                BarSeparator().padding(.horizontal, Space.xs)
            }
            .disabled(model.busy)
        }
    }

    private func chip(_ workspace: Workspace, number: Int) -> some View {
        let here = model.shownWorkspace?.id == workspace.id
        return Button { model.openWorkspace(workspace) } label: {
            HStack(spacing: Space.sm) {
                WorkspaceThumbnail(workspace: workspace, height: Metrics.control - Space.xs * 2, maxWidth: 40,
                                   cornerRadius: Metrics.insetRadius)
                Text("\(number)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
                    .padding(.trailing, labels == .named ? -Space.xs : 0)
                if labels == .named {
                    Text(workspace.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: 120, alignment: .leading).fixedSize()
                }
            }
        }
        .buttonStyle(QuietButtonStyle(selected: here, leading: Space.xs, trailing: labels == .named ? Space.md : Space.sm))
        .help("\(workspace.name) · ⌃⌥\(number)")
        .accessibilityLabel("\(workspace.name), workspace \(number)\(here ? ", on this screen" : "")")
        .contextMenu {
            Button("Open (⌃⌥\(number))") { model.openWorkspace(workspace) }
            Button("Rename…") { model.renameWorkspace(workspace) }
            Button("Move Left") { store.move(workspace.id, by: -1) }.disabled(number == 1)
            Button("Move Right") { store.move(workspace.id, by: 1) }.disabled(number == store.workspaces.count)
            Divider()
            Button("Delete", role: .destructive) { model.deleteSaved(workspace.id) }
        }
    }
}

/// A search field the height of a control, with a clear button once there's text.
struct SearchBox: View {
    let placeholder: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            GridSearchField(placeholder: placeholder, text: $text, onSubmit: onSubmit, fontSize: 13).frame(height: 20)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Space.sm).frame(height: Metrics.control)
        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
    }
}

/// ⌘O: workspaces, then layouts, each drawn as its arrangement, with saving at the bottom.
struct SavedList: View {
    @ObservedObject var model: GridEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SearchBox(placeholder: "Search workspaces and layouts", text: $model.savedSearch, onSubmit: model.confirmSearchSelection)
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        let items = model.filteredSaved
                        ForEach(items) { item in
                            if items.first(where: { $0.isWorkspace == item.isWorkspace })?.id == item.id {
                                heading(item.isWorkspace ? "Workspaces" : "Layouts", first: item.id == items.first?.id)
                            }
                            SavedRow(model: model, item: item)
                        }
                        if items.isEmpty {
                            Text(model.hasSavedItems ? "Nothing matches" : "Press ⌘S to save the windows on this screen as a workspace.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, Space.lg)
                        }
                    }
                }.frame(maxHeight: 300)
                .onChange(of: model.selectedSavedItem?.id) { _, id in
                    if let id { reader.scrollTo(id) }
                }
            }
            Divider()
            HStack(spacing: Space.xs) {
                Button { model.beginSave(.workspace) } label: { Label("New workspace", systemImage: "plus") }
                    .help("Save this screen as a new workspace (⌘⇧S)")
                Button { model.beginSave(.layout) } label: { Label("Save as layout", systemImage: "square.grid.2x2") }
                    .disabled(model.grid.filledCount == 0)
                    .help("Save the apps in this grid, not their windows")
            }
            .buttonStyle(QuietButtonStyle(trailing: Space.md)).font(.system(size: 12))
        }
        .padding(Space.md).frame(width: 320).preferredColorScheme(.light)
        .environment(\.gridPointer, nil)
    }

    private func heading(_ title: String, first: Bool) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, Space.sm).padding(.top, first ? Space.xs : Space.md).padding(.bottom, Space.xxs)
    }
}

/// One workspace or layout: its arrangement, name, and size. Delete appears on hover.
private struct SavedRow: View {
    @ObservedObject var model: GridEditorModel
    let item: GridEditorModel.SavedItem
    @State private var hovered = false

    var body: some View {
        let selected = model.selectedSavedItem?.id == item.id
        let here = item.isWorkspace && item.id == model.shownWorkspace?.id
        Button { model.open(item) } label: {
            HStack(spacing: Space.md) {
                preview.frame(width: 40, height: GridLayoutPreview.size.height)
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if here {
                    Text("Here").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, Space.xs + Space.xxs).padding(.vertical, Space.xxs)
                        .background(Color.black.opacity(0.06), in: Capsule())
                }
                Spacer(minLength: Space.sm)
                // Delete takes the size's place on hover, inside the row.
                Text(summary).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    .opacity(hovered ? 0 : 1)
            }
            .padding(.horizontal, Space.sm).frame(height: DesktopGridView.rowHeight + Space.xs).contentShape(Rectangle())
        }
        .buttonStyle(AppRowStyle(selected: selected))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .overlay(alignment: .trailing) {
            if hovered {
                Button { model.deleteSaved(item.id) } label: {
                    Image(systemName: "trash").frame(width: Metrics.control - Space.sm, height: Metrics.control - Space.sm)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, Space.xs)
                .help(item.isWorkspace ? "Delete workspace" : "Delete layout")
            }
        }
        .accessibilityAction(named: item.isWorkspace ? "Delete workspace" : "Delete layout") { model.deleteSaved(item.id) }
        .onHover { hovered = $0 }
        .id(item.id)
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .workspace(let workspace):
            WorkspaceThumbnail(workspace: workspace, height: GridLayoutPreview.size.height, maxWidth: 40, cornerRadius: Metrics.insetRadius)
        case .layout(let layout): GridLayoutPreview(grid: layout.grid, selectedCell: nil)
        }
    }

    private var summary: String {
        switch item.kind {
        case .workspace(let workspace):
            let windows = "\(workspace.windowCount) window\(workspace.windowCount == 1 ? "" : "s")"
            return workspace.screens.count > 1 ? "\(windows) · \(workspace.screens.count) screens" : windows
        case .layout(let layout): return "\(layout.grid.filledCount) app\(layout.grid.filledCount == 1 ? "" : "s")"
        }
    }
}
