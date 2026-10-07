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
    var height: CGFloat = Metrics.control
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: capsule ? height / 2 : height > Metrics.control ? Metrics.dockControlRadius : Metrics.controlRadius)
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .padding(.horizontal, Space.md).frame(minHeight: height)
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
    var height: CGFloat = Metrics.control
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary)
            .padding(.leading, leading).padding(.trailing, trailing)
            .frame(minWidth: height, minHeight: height)
            .background {
                PointerHover { hovered in
                    RoundedRectangle(cornerRadius: height > Metrics.control ? Metrics.dockControlRadius : Metrics.controlRadius).fill(Color.white.opacity(
                        configuration.isPressed ? 0.95 : selected ? 0.85 : hovered && enabled ? 0.6 : 0))
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
            let gridTop = top
            let availableHeight = max(160, canvas.height - gridTop - Self.footerReserve)
            let aspect = (model.display?.bounds.width ?? canvas.width) / max(1, model.display?.bounds.height ?? canvas.height)
            let width = min(max(320, canvas.width * 0.90), availableHeight * aspect)
            let gridHeight = width / aspect
            ZStack(alignment: .top) {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { if model.choosingApp { model.choosingApp = false } else { model.dismissLayer() } }
                // G shows the Layouts panel in the panes' place.
                Group {
                    if model.resizing { LayoutsPanel(model: model, size: CGSize(width: width, height: gridHeight)) }
                    else { gridCanvas(width: width, height: gridHeight) }
                }
                .frame(width: width, height: gridHeight)
                .padding(.top, gridTop).zIndex(1)
                VStack {
                    Spacer()
                    footer
                }.padding(.bottom, Space.lg).padding(.horizontal, Space.xl).zIndex(3)
                if model.showingShortcuts {
                    ShortcutSheet().padding(.top, gridTop + Space.xl).zIndex(4)
                        .onTapGesture { model.closeLayers() }
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .coordinateSpace(name: gridRootSpace)
            .background(PointerTracker { pointer = $0 })
            .environment(\.gridPointer, pointer)
            .onChange(of: pointer) { _, point in
                // The grid is centered horizontally near the top.
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

    /// Room below the grid for a pill and the dock.
    private static let footerReserve: CGFloat = Metrics.dockHeight + Metrics.pillHeight + Space.lg * 2 + Space.sm

    /// The dock: the main actions, labeled with their shortcuts, so what you can do is in view.
    private var dock: some View {
        ViewThatFits(in: .horizontal) {
            dockBar(labels: true)
            dockBar(labels: false)
        }
    }

    private func dockBar(labels: Bool) -> some View {
        HStack(spacing: Space.xs) {
            if let store = model.workspaces {
                // Above the rest of the dock, so the fanned-out cards draw over it.
                WorkspaceStack(store: store, model: model, captionAbove: true).zIndex(1)
            }
            Button { if model.resizing { model.closeLayers() } else { model.beginResize() } } label: {
                HStack(spacing: Space.sm) {
                    GridLayoutPreview(grid: model.grid, selectedCell: model.selectedCell)
                    if labels { Text("Layouts") }
                    keycap("G")
                }
            }
            .buttonStyle(QuietButtonStyle(selected: model.resizing, leading: Space.xs, trailing: Space.sm, height: Metrics.dockControl))
            .help("Layouts and grid size (G)").disabled(model.busy)
            dockButton("Add pane", systemImage: "plus", key: "⌘K", labels: labels, action: model.addApp)
            dockButton("Tile all", systemImage: "square.grid.2x2", key: "⌘T", labels: labels) { model.tileAll() }
            BarSeparator().padding(.horizontal, Space.xs)
            saveButton(labels: labels)
            if model.busy {
                Button("Stop", action: model.cancel).buttonStyle(GridButtonStyle(height: Metrics.dockControl))
            } else {
                Button(action: model.openGrid) {
                    HStack(spacing: Space.sm) {
                        Text("Apply")
                        keycap("↵").colorScheme(.dark)
                    }
                }
                .buttonStyle(GridButtonStyle(primary: true, height: Metrics.dockControl))
                .disabled((model.grid.filledCount == 0 && model.originalGrid.filledCount == 0) || model.desktop == nil)
                .padding(.leading, Space.xs)
            }
            moreButton
        }
        .padding(Metrics.barPadding)
        .glassSurface(RoundedRectangle(cornerRadius: Metrics.dockRadius), reduceTransparency: reduceTransparency)
        .fixedSize()
    }

    private func dockButton(_ title: String, systemImage: String, key: String, labels: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: systemImage)
                if labels { Text(title) }
                keycap(key)
            }
        }
        .buttonStyle(QuietButtonStyle(leading: Space.sm + Space.xxs, trailing: Space.sm, height: Metrics.dockControl))
        .help("\(title) (\(key))").disabled(model.busy)
        .accessibilityLabel(title)
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

    private var moreButton: some View {
        Button { showMoreMenu() } label: { Image(systemName: "ellipsis") }
            .buttonStyle(QuietButtonStyle(height: Metrics.dockControl))
            .help("More").disabled(model.busy)
            .accessibilityLabel("More actions")
    }

    /// Actions only, with their shortcuts aligned right.
    private func showMoreMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [], enabled: Bool = true, action: @escaping () -> Void) {
            menu.addItem(GridMenuItem(title, key: key, modifiers: modifiers, enabled: enabled, action: action))
        }
        add("Tile all", "t", .command) { model.tileAll() }
        add("Realign panes", "r", .command) { model.realign() }
        add("Grid size…", "g") { model.beginResize() }
        for screen in model.otherScreens {
            add("Bring \(windowCount(screen.windows.count)) from \(screen.name)") { model.bring(from: screen.id) }
        }
        menu.addItem(.separator())
        add("Undo", "z", .command) { model.undo() }
        add("Undo last window arrangement", enabled: model.manager.undoLabel != nil) { model.manager.undo() }
        add("Close all panes on Apply", "\u{8}", [.command, .shift]) { model.removeAllPanes() }
        menu.addItem(.separator())
        add("Keyboard Shortcuts", "?") { model.toggleShortcuts() }
        if Display.all.count > 1 || model.putBackAutomatically {
            let putBack = NSMenuItem(title: "Put windows back when a screen reconnects", action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for (title, automatic) in [("Ask first", false), ("Automatically", true)] {
                let item = GridMenuItem(title) { model.putBackAutomatically = automatic }
                item.state = model.putBackAutomatically == automatic ? .on : .off
                choices.addItem(item)
            }
            putBack.submenu = choices
            menu.addItem(putBack)
        }
        // A downloaded update holds Sparkle's session open until it installs, so checking again would do nothing.
        if model.updateReady, let version = model.availableUpdate, let update = model.onUpdate {
            add("Restart to Install Tilez \(version)", action: update)
        } else if let check = model.onCheckForUpdates {
            add("Check for Updates…", action: check)
        }
        add("Quit Tilez", "q", .command) { NSApp.terminate(nil) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Saving, workspaces, and layouts share one button and one popup, which opens upward.
    private func saveButton(labels: Bool) -> some View {
        Button(action: model.beginSaved) {
            HStack(spacing: Space.sm) {
                Image(systemName: "rectangle.3.group")
                    .overlay(alignment: .topTrailing) {
                        if model.workspaceModified {
                            Circle().fill(Color.primary).frame(width: 6, height: 6).offset(x: Space.xs, y: -Space.xxs)
                        }
                    }
                if labels { Text("Workspaces") }
                keycap("⌘S")
            }
        }
        .buttonStyle(QuietButtonStyle(selected: model.showingSaved || model.saving, leading: Space.sm + Space.xxs, trailing: Space.sm,
                                      height: Metrics.dockControl))
        .help(model.shownWorkspace.map { "Workspace “\($0.name)”\(model.workspaceModified ? ", edited" : "") · Save, workspaces, and layouts (⌘S, ⌘O)" }
              ?? "Save, workspaces, and layouts (⌘S, ⌘O)")
        .disabled(model.busy)
        .accessibilityLabel(model.workspaceModified ? "Workspaces and layouts, unsaved changes" : "Workspaces and layouts")
        .popover(isPresented: Binding(get: { model.showingSaved || model.saving }, set: { if !$0 { model.closeLayers() } }),
                 arrowEdge: .top) {
            Group {
                if model.saving { savePopover } else { SavedList(model: model) }
            }
            .onDisappear { model.onFocusGrid?() }
        }
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
            dock.padding(.top, Space.sm)
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
    var cell: CGFloat = 16
    private var step: CGFloat { cell + Space.xs }
    var body: some View {
        VStack(spacing: Space.xs) {
            ForEach(0..<DesktopGrid.maxRows, id: \.self) { row in
                HStack(spacing: Space.xs) {
                    ForEach(0..<DesktopGrid.maxColumns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: Space.xs)
                            .fill(column < columns && row < rows ? gridAccent : Color.black.opacity(0.1))
                            .frame(width: cell, height: cell)
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
/// The first nine workspaces as a stack of overlapping thumbnails at the start of the bar.
/// Hovering fans them out on a tray over the bar, with the pointed-at one's number and name
/// below it; the bar itself never changes width, so nothing moves under the pointer.
struct WorkspaceStack: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var model: GridEditorModel
    @Environment(\.gridPointer) private var pointer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// In the dock the caption sits above the stack rather than below it.
    var captionAbove = false
    @State private var expanded: Bool
    @State private var hovered: Int?
    static let card = CGSize(width: 40, height: Metrics.control - Space.xs * 2)
    /// How much of each card behind the front one shows while stacked.
    static let peek: CGFloat = 7
    static let peeking = 4
    static let captionHeight: CGFloat = 24

    init(store: WorkspaceStore, model: GridEditorModel, captionAbove: Bool = false, expanded: Bool = false, hovered: Int? = nil) {
        self.store = store; self.model = model; self.captionAbove = captionAbove
        _expanded = State(initialValue: expanded); _hovered = State(initialValue: hovered)
    }

    var body: some View {
        let shown = Array(store.workspaces.prefix(9))
        if !shown.isEmpty {
            let stacked = Self.card.width + Self.peek * CGFloat(min(shown.count, Self.peeking) - 1)
            let fanned = CGFloat(shown.count) * Self.card.width + CGFloat(shown.count - 1) * Space.xs
            HStack(spacing: Space.xs) {
                ZStack(alignment: .topLeading) {
                    // The tray the cards fan out onto, inset like a control.
                    RoundedRectangle(cornerRadius: Metrics.controlRadius)
                        .fill(Color.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                        .frame(width: fanned + Space.xs * 2, height: Metrics.control)
                        .opacity(expanded ? 1 : 0)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, workspace in
                        card(workspace, number: index + 1)
                            .offset(x: Space.xs + (expanded ? CGFloat(index) * (Self.card.width + Space.xs)
                                                            : CGFloat(min(index, Self.peeking - 1)) * Self.peek),
                                    y: Space.xs)
                            .opacity(expanded || index < Self.peeking ? 1 : 0)
                            .zIndex(Double(shown.count - index))
                    }
                    if expanded, let hovered, shown.indices.contains(hovered) {
                        caption(shown[hovered], number: hovered + 1)
                            .offset(x: CGFloat(hovered) * (Self.card.width + Space.xs),
                                    y: captionAbove ? -(Self.captionHeight + Space.sm) : Metrics.control + Space.sm)
                            .zIndex(Double(shown.count + 1))
                    }
                }
                .frame(width: stacked + Space.xs * 2, height: Metrics.control, alignment: .topLeading)
                .background {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(gridRootSpace))
                        Color.clear.onChange(of: pointer) { _, point in track(point, frame: frame, fanned: fanned, count: shown.count) }
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: expanded)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Workspaces")
                BarSeparator().padding(.horizontal, Space.xs)
            }
            .disabled(model.busy)
        }
    }

    /// Fanned out while the pointer is over the stack, or over the tray once it's open.
    private func track(_ point: CGPoint?, frame: CGRect, fanned: CGFloat, count: Int) {
        let tray = CGRect(x: frame.minX, y: frame.minY - Space.sm, width: fanned + Space.xs * 2 + Space.sm,
                          height: frame.height + Space.sm * 2)
        let inside = point.map { (expanded ? tray : frame).contains($0) } ?? false
        if inside != expanded { expanded = inside }
        hovered = inside ? point.map { Int(($0.x - frame.minX - Space.xs) / (Self.card.width + Space.xs)) }
            .flatMap { (0..<count).contains($0) ? $0 : nil } : nil
    }

    private func card(_ workspace: Workspace, number: Int) -> some View {
        let here = model.shownWorkspace?.id == workspace.id
        return Button { model.openWorkspace(workspace) } label: {
            WorkspaceThumbnail(workspace: workspace, height: Self.card.height, maxWidth: Self.card.width,
                               cornerRadius: Metrics.insetRadius, opaque: true)
                .frame(width: Self.card.width, height: Self.card.height)
                .overlay {
                    // A ring marks the workspace this screen shows; a hairline separates the others.
                    RoundedRectangle(cornerRadius: Metrics.insetRadius)
                        .strokeBorder(here ? gridAccent : Color.black.opacity(0.12), lineWidth: here ? 1.5 : 1)
                }
                .shadow(color: .black.opacity(expanded ? 0 : 0.12), radius: 2, x: -1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func caption(_ workspace: Workspace, number: Int) -> some View {
        HStack(spacing: Space.sm) {
            Text("\(number)").monospacedDigit().foregroundStyle(.secondary)
            Text(workspace.name).lineLimit(1)
            Text("⌃⌥\(number)").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, Space.sm).frame(height: Self.captionHeight)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: Metrics.rowRadius))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .fixedSize()
        .allowsHitTesting(false)
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

/// The Save button's popup: saving at the top, then your workspaces and layouts. A search field
/// appears once the list is long; typing filters it either way.
struct SavedList: View {
    @ObservedObject var model: GridEditorModel

    var body: some View {
        let items = model.filteredSaved
        VStack(alignment: .leading, spacing: Space.xxs) {
            if let shown = model.shownWorkspace {
                ActionRow(title: "Save “\(shown.name)”", systemImage: "bookmark.fill", key: "⌘S") { model.saveWorkspace() }
            }
            ActionRow(title: "New workspace…", systemImage: "plus", key: model.shownWorkspace == nil ? "⌘S" : "⌘⇧S") {
                model.beginSave(.workspace)
            }
            ActionRow(title: "Save as layout…", systemImage: "square.grid.2x2", key: "") { model.beginSave(.layout) }
                .disabled(model.grid.filledCount == 0)
                .help("Keeps the apps in this grid, not their windows")
            if model.hasSavedItems {
                Divider().padding(.vertical, Space.xs).padding(.horizontal, Space.sm)
                if model.saved.count + (model.workspaces?.workspaces.count ?? 0) > 8 || !model.savedSearch.isEmpty {
                    SearchBox(placeholder: "Search", text: $model.savedSearch, onSubmit: model.confirmSearchSelection)
                        .padding(.bottom, Space.xs)
                }
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            let mixed = items.contains(where: \.isWorkspace) && items.contains(where: { !$0.isWorkspace })
                            ForEach(items) { item in
                                // Headings only when there's both kinds to tell apart.
                                if mixed, items.first(where: { $0.isWorkspace == item.isWorkspace })?.id == item.id {
                                    heading(item.isWorkspace ? "Workspaces" : "Layouts", first: item.id == items.first?.id)
                                }
                                SavedRow(model: model, item: item)
                            }
                            if items.isEmpty {
                                Text("Nothing matches").font(.system(size: 13)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, Space.md)
                            }
                        }
                    }.frame(maxHeight: 320).fixedSize(horizontal: false, vertical: true)
                    .onChange(of: model.selectedSavedItem?.id) { _, id in
                        if let id { reader.scrollTo(id) }
                    }
                }
            }
        }
        .padding(Space.sm).frame(width: 280).preferredColorScheme(.light)
        .environment(\.gridPointer, nil)
    }

    private func heading(_ title: String, first: Bool) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, Space.sm).padding(.top, first ? 0 : Space.sm).padding(.bottom, Space.xxs)
    }
}

/// A menu-like row: an icon, a title, and its shortcut on the right.
private struct ActionRow: View {
    let title: String
    let systemImage: String
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                Image(systemName: systemImage).frame(width: 16).foregroundStyle(.secondary)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: Space.md)
                Text(key).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.sm).frame(height: Metrics.control).contentShape(Rectangle())
        }
        .buttonStyle(AppRowStyle())
    }
}

/// One workspace or layout: its arrangement and name. Delete appears on hover.
private struct SavedRow: View {
    @ObservedObject var model: GridEditorModel
    let item: GridEditorModel.SavedItem
    @State private var hovered = false

    var body: some View {
        let selected = model.selectedSavedItem?.id == item.id
        let here = item.isWorkspace && item.id == model.shownWorkspace?.id
        Button { model.open(item) } label: {
            HStack(spacing: Space.sm) {
                preview.frame(width: 40, height: GridLayoutPreview.size.height)
                Text(item.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: Space.sm)
                if here && !hovered {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityLabel("On this screen")
                }
            }
            .padding(.leading, Space.xs).padding(.trailing, Space.sm)
            .frame(height: Metrics.control + Space.xs).contentShape(Rectangle())
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
}

/// A menu item that runs a closure. Its key equivalent is only shown: the menu isn't attached to
/// the menu bar, so the grid's own key handling stays the only place a shortcut runs.
private final class GridMenuItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], enabled: Bool = true, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self; isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("Not supported") }
    @objc private func invoke() { run() }
}

/// Every shortcut in one place: those that work anywhere, and those inside the grid.
struct ShortcutSheet: View {
    private let anywhere = [("⌃⌥Space", "Show or hide the grid"), ("⌃⌥N", "Quick add a tile"), ("⌃⌥R", "Realign windows"),
                            ("⌃⌥W", "Open a workspace"), ("⌃⌥1–9", "Switch workspace"), ("⌃⌥S", "Save the workspace"),
                            ("⌃⌥⇧S", "Save a new workspace"), ("⌃⌥Return", "Enlarge a window")]
    private let grid = [("Arrows", "Select a pane"), ("⌥ Arrows", "Split"), ("⌥⇧ Arrows", "Merge"), ("⇧ Arrows", "Move"),
                        ("⌘K", "Add a pane"), ("⌘T", "Tile all"), ("⌘R", "Realign"), ("G", "Grid size"),
                        ("⌘S / ⌘O", "Save / open"), ("⌘Z", "Undo"), ("↵", "Apply"), ("Esc", "Close")]

    var body: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            column("Anywhere", anywhere)
            column("In the grid", grid)
        }
        .padding(Space.lg)
        .glassSurface(RoundedRectangle(cornerRadius: Metrics.barRadius))
        .fixedSize()
        .preferredColorScheme(.light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }

    private func column(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { key, label in
                HStack(spacing: Space.md) {
                    Text(key).font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, Space.xs + Space.xxs).fixedSize()
                        .frame(width: 96, height: 22, alignment: .leading)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: Space.xs))
                    Text(label).font(.system(size: 13))
                }
            }
        }
    }
}

/// G: presets and a custom grid in the panes' place, each card showing where your windows would
/// go. 1–9 picks a preset, arrows move, Return picks the highlighted card, ⇧ arrows size the grid.
struct LayoutsPanel: View {
    @ObservedObject var model: GridEditorModel
    let size: CGSize
    private static let labelHeight: CGFloat = 32

    var body: some View {
        let columns = GridEditorModel.layoutColumns
        let rows = Int((Double(LayoutPreset.all.count + 1) / Double(columns)).rounded(.up))
        let header: CGFloat = 28
        // Around each drawing: its own inset, the card's padding, and the name and detail below it.
        let chrome = CGSize(width: (Space.md + Space.sm) * 2, height: (Space.md + Space.sm) * 2 + Space.sm + Self.labelHeight)
        let cardWidth = (size.width - Space.xl * 2 - Space.md * CGFloat(columns - 1)) / CGFloat(columns)
        let roomPerRow = (size.height - Space.xl * 2 - header - Space.lg - Space.md * CGFloat(rows - 1)) / CGFloat(rows)
        let aspect = size.width / max(1, size.height)
        let preview = CGSize(width: min(cardWidth - chrome.width, (roomPerRow - chrome.height) * aspect),
                             height: min((cardWidth - chrome.width) / aspect, roomPerRow - chrome.height))
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text("Layouts").font(.system(size: 20, weight: .semibold))
                Text("\(model.grid.filledCount) window\(model.grid.filledCount == 1 ? "" : "s") on this screen")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text("1–9 or ↵ choose  ·  ⇧ arrows size the grid  ·  Esc close")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(height: header)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: Space.md), count: columns), spacing: Space.md) {
                ForEach(LayoutPreset.all.indices, id: \.self) { index in
                    presetCard(index, preview: preview)
                }
                customCard(preview: preview)
            }
        }
        .padding(Space.xl)
        .frame(width: size.width, height: size.height, alignment: .top)
        .glassSurface(RoundedRectangle(cornerRadius: Metrics.paneRadius + Space.sm))
        .preferredColorScheme(.light)
    }

    private func presetCard(_ index: Int, preview: CGSize) -> some View {
        let preset = LayoutPreset.all[index]
        let windows = model.grid.readingOrder.map { model.grid.slots[$0] }.filter { $0.app != nil }
        let dropped = windows.count - preset.frames.count
        return card(index, title: preset.name, detail: model.grid.matches(preset) ? "Current"
                        : dropped > 0 ? "Leaves out \(dropped) window\(dropped == 1 ? "" : "s")" : "\(preset.frames.count) pane\(preset.frames.count == 1 ? "" : "s")",
                    key: index < 9 ? "\(index + 1)" : nil, warning: dropped > 0) {
            ZStack(alignment: .topLeading) {
                let frames = DesktopGrid.drawingFrames(preset, in: preview)
                ForEach(frames.indices, id: \.self) { slot in
                    let frame = frames[slot]
                    RoundedRectangle(cornerRadius: Metrics.rowRadius)
                        .fill(Color.white.opacity(slot < windows.count ? 0.95 : 0.5))
                        .overlay {
                            if slot < windows.count, let app = windows[slot].app {
                                Image(nsImage: model.icon(for: app)).resizable().interpolation(.high)
                                    .frame(width: min(28, frame.width * 0.5, frame.height * 0.5), height: min(28, frame.width * 0.5, frame.height * 0.5))
                            }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: preview.width, height: preview.height, alignment: .topLeading)
        } choose: { model.choosePreset(index) }
    }

    private func customCard(preview: CGSize) -> some View {
        let dropped = model.grid.filledCount - model.draftColumns * model.draftRows
        return card(model.customLayoutIndex, title: "Custom grid · \(model.draftColumns) × \(model.draftRows)",
                    detail: dropped > 0 ? "Leaves out \(dropped) window\(dropped == 1 ? "" : "s")" : "Click a size, or ⇧ arrows",
                    key: nil, warning: dropped > 0) {
            GridSizePicker(columns: model.draftColumns, rows: model.draftRows,
                           hover: { c, r in model.draftColumns = c; model.draftRows = r; model.highlightedLayout = model.customLayoutIndex },
                           select: model.resize(columns:rows:),
                           cell: max(10, min(22, (preview.height - Space.xs * 3) / 4)))
                .frame(width: preview.width, height: preview.height)
        } choose: { model.confirmResize() }
    }

    private func card<Preview: View>(_ index: Int, title: String, detail: String, key: String?, warning: Bool,
                                     @ViewBuilder preview: () -> Preview, choose: @escaping () -> Void) -> some View {
        let highlighted = model.highlightedLayout == index
        return Button(action: { model.highlightedLayout = index; choose() }) {
            VStack(alignment: .leading, spacing: Space.sm) {
                preview()
                    .padding(Space.md)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: Metrics.controlRadius + Space.xs))
                HStack(spacing: Space.sm) {
                    if let key {
                        Text(key).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(highlighted ? 0.85 : 0.08), in: RoundedRectangle(cornerRadius: Space.xs))
                            .foregroundStyle(highlighted ? Color.white : Color.primary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(detail).font(.system(size: 11)).foregroundStyle(warning ? Color.orange : Color.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, Space.xs).frame(height: Self.labelHeight)
            }
            .padding(Space.sm)
            .background(Color.white.opacity(highlighted ? 0.75 : 0.35), in: RoundedRectangle(cornerRadius: Metrics.controlRadius + Space.xs + Space.sm))
            .overlay(RoundedRectangle(cornerRadius: Metrics.controlRadius + Space.xs + Space.sm)
                .strokeBorder(highlighted ? gridAccent : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(highlighted ? [.isSelected] : [])
    }
}

private extension DesktopGrid {
    /// A preset's panes in reading order, laid out in `size` with a small gap, for a card's drawing.
    static func drawingFrames(_ preset: LayoutPreset, in size: CGSize) -> [CGRect] {
        let gap = CGSize(width: 4 / max(1, size.width), height: 4 / max(1, size.height))
        return DesktopGrid(panes: preset.frames.map { _ in GridSlot() }, frames: preset.frames).arranged(in: preset, gap: gap)
            .frames(in: CGRect(origin: .zero, size: size))
    }
}
