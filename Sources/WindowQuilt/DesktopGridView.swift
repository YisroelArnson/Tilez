import AppKit
import SwiftUI
import QuiltCore

private let gridBlue = Color(red: 0.02, green: 0.39, blue: 1)

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

private struct GridButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(primary ? Color.white : Color.primary)
            .padding(.horizontal, 15).frame(minHeight: 42)
            .background(primary ? gridBlue : Color.white.opacity(configuration.isPressed ? 0.75 : 0.4),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(primary ? Color.clear : Color.white.opacity(0.6)))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion && NSEvent.pressedMouseButtons != 0 ? 0.96 : 1)
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
    @FocusState private var searchFocused: Bool
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            // Keep the composition readable on large desktops instead of shrinking the bar
            // to a tiny island above screen-sized cells. All positions share this canvas.
            let scale = max(1, min(2.2, proxy.size.width / 1600))
            let canvas = CGSize(width: proxy.size.width / scale, height: proxy.size.height / scale)
            let width = max(320, canvas.width * 0.82)
            let top = max(26, min(64, canvas.height * 0.075))
            let gridTop = top + 130
            let gridHeight = max(160, canvas.height - gridTop - 78)
            ZStack(alignment: .top) {
                Color.black.opacity(0.12).ignoresSafeArea()
                    .onTapGesture { if model.choosingApp { model.choosingApp = false } else { model.dismissLayer() } }
                VStack(spacing: 0) {
                    toolbar
                    Text("Drag to swap  ·  Shift-drag to repeat an app")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .padding(.top, 14)
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
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .tint(gridBlue)
        .preferredColorScheme(.light)
        .onChange(of: model.choosingApp) { _, showing in searchFocused = showing }
        .onChange(of: model.saving) { _, showing in nameFocused = showing }
        .onExitCommand { model.dismissLayer() }
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            bar(compact: false)
            bar(compact: true)
        }
        .padding(.horizontal, 24)
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 18) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 25, weight: .medium)).foregroundStyle(gridBlue)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Window Quilt")
            if !compact { Text("Grid").font(.system(size: 15, weight: .medium)) }
            GridSizePicker(columns: model.grid.columns, rows: model.grid.rows) { c, r in model.resize(columns: c, rows: r) }
                .disabled(model.busy)
            Text("\(model.grid.columns) × \(model.grid.rows)")
                .font(.system(size: 14, weight: .medium)).monospacedDigit().frame(width: 42)
            Rectangle().fill(.black.opacity(0.10)).frame(width: 1, height: 34)
            Button(action: model.addApp) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                    Text(compact ? "App" : "Add app")
                    if !compact { keycap("⌘K") }
                }
            }.keyboardShortcut("k", modifiers: .command).disabled(model.busy)
            Button {
                model.saveName = "\(model.grid.columns) × \(model.grid.rows) grid"
                model.saving.toggle(); model.choosingApp = false; model.showingSaved = false
            } label: { Label("Save", systemImage: "bookmark") }
                .disabled(model.grid.filledCount == 0 || model.busy)
                .popover(isPresented: $model.saving, arrowEdge: .bottom) { savePopover }
            if !model.saved.isEmpty {
                Button { model.showingSaved.toggle(); model.choosingApp = false } label: {
                    Image(systemName: "bookmark.fill").accessibilityLabel("Saved grids")
                }
                .help("Saved grids")
                .popover(isPresented: $model.showingSaved, arrowEdge: .bottom) { savedPopover }
            }
            if model.busy {
                Button("Stop", action: model.cancel)
            } else {
                Button(action: model.openGrid) {
                    HStack(spacing: 12) {
                        Text(model.hasOpened ? "Apply grid" : "Open grid")
                        Image(systemName: "return")
                    }
                }.buttonStyle(GridButtonStyle(primary: true))
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.grid.filledCount == 0 || model.desktop == nil)
            }
            Menu {
                Button("New empty grid", action: model.newGrid).keyboardShortcut("n")
                Button("Undo grid edit", action: model.undo).keyboardShortcut("z")
                Button("Undo last window arrangement") { model.manager.undo() }
                    .disabled(model.manager.undoLabel == nil)
                Divider()
                Text("Show or hide Quilt: ⌃⌥Space")
                Button("Close", action: { model.onDismiss?() })
                Button("Quit Window Quilt") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 16) }
                .menuStyle(.borderlessButton).fixedSize().help("More actions")
                .disabled(model.busy)
        }
        .buttonStyle(GridButtonStyle())
        .padding(14)
        .background {
            GridGlass(material: .popover)
                .overlay(Color.white.opacity(reduceTransparency ? 1 : 0.25))
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.8)))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func gridCanvas(width: CGFloat, height: CGFloat) -> some View {
        let gap: CGFloat = 10
        let cellWidth = (width - CGFloat(model.grid.columns - 1) * gap) / CGFloat(model.grid.columns)
        let cellHeight = (height - CGFloat(model.grid.rows - 1) * gap) / CGFloat(model.grid.rows)
        return ZStack(alignment: .topLeading) {
            ForEach(model.grid.slots.indices, id: \.self) { index in
                let x = CGFloat(index % model.grid.columns) * (cellWidth + gap)
                let y = CGFloat(index / model.grid.columns) * (cellHeight + gap)
                cell(index, compact: cellHeight < 170 || cellWidth < 220)
                    .frame(width: cellWidth, height: cellHeight)
                    .offset(x: x, y: y)
                    .opacity(dragSource == index ? 0.45 : 1)
                    .onHover { hovering in hoveredCell = hovering ? index : (hoveredCell == index ? nil : hoveredCell) }
                    .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("grid"))
                        .onChanged { value in
                            guard !model.busy, model.grid.slots[index].app != nil else { return }
                            if dragSource == nil {
                                dragSource = index; suppressCellClick = true
                                repeatDrag = NSEvent.modifierFlags.contains(.shift)
                                model.choosingApp = false
                            }
                            dragTranslation = value.translation
                            let c = Int(floor(value.location.x / (cellWidth + gap)))
                            let r = Int(floor(value.location.y / (cellHeight + gap)))
                            dragTarget = (0..<model.grid.columns).contains(c) && (0..<model.grid.rows).contains(r)
                                ? r * model.grid.columns + c : nil
                            repeatDrag = NSEvent.modifierFlags.contains(.shift)
                        }
                        .onEnded { _ in
                            if let source = dragSource, let target = dragTarget {
                                model.move(from: source, to: target, repeating: repeatDrag)
                            }
                            dragSource = nil; dragTarget = nil; dragTranslation = .zero
                            DispatchQueue.main.async { suppressCellClick = false }
                        })
            }
            if let source = dragSource, let app = model.grid.slots[source].app {
                HStack(spacing: 10) {
                    Image(nsImage: model.icon(for: app)).resizable().frame(width: 36, height: 36)
                    Text(app.name).font(.system(size: 15, weight: .medium))
                    if repeatDrag { Image(systemName: "plus.circle.fill").foregroundStyle(gridBlue) }
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12, y: 5)
                    .offset(x: CGFloat(source % model.grid.columns) * (cellWidth + gap) + cellWidth / 2 - 60 + dragTranslation.width,
                            y: CGFloat(source / model.grid.columns) * (cellHeight + gap) + cellHeight / 2 - 25 + dragTranslation.height)
                    .allowsHitTesting(false).zIndex(5)
            }
        }.frame(width: width, height: height, alignment: .topLeading).coordinateSpace(name: "grid")
    }

    private func cell(_ index: Int, compact: Bool) -> some View {
        let app = model.grid.slots[index].app
        let selected = model.selectedCell == index || dragTarget == index
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(reduceTransparency ? Color(white: 0.25) : Color.white.opacity(hoveredCell == index ? 0.18 : 0.10))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? gridBlue : .white.opacity(0.65), lineWidth: selected ? 2.5 : 1)
            Button { if dragSource == nil && !suppressCellClick { model.choose(index) } } label: {
                VStack(spacing: compact ? 8 : 13) {
                    if let app {
                        Image(nsImage: model.icon(for: app)).resizable().interpolation(.high)
                            .frame(width: compact ? 42 : 64, height: compact ? 42 : 64)
                            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                        Text(app.name).font(.system(size: compact ? 14 : 17, weight: .medium)).lineLimit(1)
                    } else {
                        Image(systemName: "plus").font(.system(size: compact ? 20 : 27, weight: .light))
                            .frame(width: compact ? 38 : 50, height: compact ? 38 : 50)
                            .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1.5))
                        Text("Choose an app").font(.system(size: compact ? 12 : 16, weight: .medium))
                    }
                }.foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.busy)
                .accessibilityLabel("Cell \(index + 1), \(app?.name ?? "empty"). Choose app")
                .popover(isPresented: Binding(get: { model.choosingApp && model.selectedCell == index },
                                              set: { if !$0 { model.choosingApp = false } }), arrowEdge: .trailing) {
                    appPopover(index)
                }
            VStack {
                HStack {
                    Text("\(index + 1)").font(.system(size: 12, weight: .medium)).opacity(0.8)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium))
                }
                Spacer()
            }.foregroundStyle(.white).padding(17).allowsHitTesting(false)
        }
        .contextMenu {
            Button("Choose app…") { model.choose(index) }
            if app != nil {
                Button("Repeat in empty cells") {
                    for target in model.grid.slots.indices where model.grid.slots[target].app == nil {
                        model.move(from: index, to: target, repeating: true)
                    }
                }
                Button("Remove from grid") { model.clear(index) }
            }
        }
    }

    private func appPopover(_ index: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps…", text: $model.search).textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = model.filteredApps.first { model.assign(first.app) } }
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.padding(10).background(.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.filteredApps) { choice in
                        Button { model.assign(choice.app) } label: {
                            HStack(spacing: 12) {
                                Image(nsImage: model.icon(for: choice.app)).resizable().frame(width: 30, height: 30)
                                Text(choice.app.name).font(.system(size: 14)).lineLimit(1)
                                Spacer()
                                if model.grid.slots[index].app == choice.app { Image(systemName: "checkmark").foregroundStyle(gridBlue) }
                            }.padding(.horizontal, 8).padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(AppRowStyle())
                    }
                    if model.filteredApps.isEmpty { Text("No apps found").foregroundStyle(.secondary).padding(20) }
                }
            }.frame(height: min(280, CGFloat(max(1, model.filteredApps.count)) * 47))
            if model.grid.slots[index].app != nil {
                Divider()
                Button("Remove from grid") { model.clear(index) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }.padding(12).frame(width: 280).preferredColorScheme(.light)
            .onAppear { searchFocused = true }
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
    }

    private var savedPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved grids").font(.system(size: 15, weight: .semibold))
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.saved) { item in
                        HStack {
                            Button { model.load(item) } label: {
                                HStack {
                                    Image(systemName: "square.grid.2x2").foregroundStyle(gridBlue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).lineLimit(1)
                                        Text("\(item.grid.columns) × \(item.grid.rows) · \(item.grid.filledCount) apps")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }.padding(8).contentShape(Rectangle())
                            }.buttonStyle(AppRowStyle())
                            Button { model.deleteSaved(item.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete saved grid")
                        }
                    }
                }
            }.frame(maxHeight: 270)
        }.padding(16).frame(width: 310).preferredColorScheme(.light)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !model.trusted {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised")
                    Text("Allow Accessibility so Quilt can arrange your windows.")
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
            HStack(spacing: 8) {
                keycap("Esc"); Text(model.busy ? "to stop" : "to close")
                Text("·").padding(.horizontal, 4)
                keycap("⌃⌥Space"); Text("to bring it back")
            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.14)))
    }
}

private struct AppRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { AppRowBody(configuration: configuration) }
    private struct AppRowBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        var body: some View {
            configuration.label.foregroundStyle(.primary)
                .background(gridBlue.opacity(configuration.isPressed ? 0.18 : hovered ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovered = $0 }
        }
    }
}

private struct GridSizePicker: View {
    let columns: Int
    let rows: Int
    let select: (Int, Int) -> Void
    @State private var preview: (Int, Int)?
    @State private var dragging = false
    private let step: CGFloat = 13
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<DesktopGrid.maxRows, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<DesktopGrid.maxColumns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(column < (preview?.0 ?? columns) && row < (preview?.1 ?? rows) ? gridBlue : Color.black.opacity(0.12))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .padding(5).background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): if !dragging { preview = dimensions(point) }
            case .ended: if !dragging { preview = nil }
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in dragging = true; preview = dimensions(value.location) }
            .onEnded { value in
                let size = dimensions(value.location); select(size.0, size.1)
                dragging = false; preview = nil
            })
        .help("Drag to choose grid size · up to 6 columns and 4 rows")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Grid size, \(columns) columns by \(rows) rows")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { select(min(DesktopGrid.maxColumns, columns + 1), rows) }
            else if direction == .decrement { select(max(1, columns - 1), rows) }
        }
        .accessibilityAction(named: "Add row") { select(columns, min(DesktopGrid.maxRows, rows + 1)) }
        .accessibilityAction(named: "Remove row") { select(columns, max(1, rows - 1)) }
    }
    private func dimensions(_ point: CGPoint) -> (Int, Int) {
        (max(1, min(DesktopGrid.maxColumns, Int(floor((point.x - 5) / step)) + 1)),
         max(1, min(DesktopGrid.maxRows, Int(floor((point.y - 5) / step)) + 1)))
    }
}
