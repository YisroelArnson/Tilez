import AppKit
import SwiftUI

struct QuiltPopoverView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @ObservedObject var navigation: QuiltNavigation
    let openWindow: (Page) -> Void
    let arrangementChanged: (Bool) -> Void
    @State private var arranging: Bool
    @State private var arrangementID = UUID()

    private var runningLayouts: [RunningLayout] { manager.runningLayouts }

    init(manager: WindowManager, preferences: Preferences, navigation: QuiltNavigation,
         openWindow: @escaping (Page) -> Void, arrangementChanged: @escaping (Bool) -> Void) {
        self.manager = manager
        self.preferences = preferences
        self.navigation = navigation
        self.openWindow = openWindow
        self.arrangementChanged = arrangementChanged
        _arranging = State(initialValue: preferences.setups.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Window Quilt", systemImage: "square.grid.2x2.fill").font(.headline)
                Spacer()
                Menu {
                    Button("Settings…") { openWindow(.settings) }
                    Button("Active layouts…") { openWindow(.active) }
                    Button("Keyboard shortcuts…") { openWindow(.shortcuts) }
                    Button("Arrange selected windows…") { openWindow(.arrange) }
                    Button("Desktop snapshots…") { openWindow(.snapshots) }
                    Menu("Move focused window") {
                        ForEach(Command.allCases.filter { $0 != .tile && $0 != .undo }) { command in
                            Button(command.title) { manager.execute(command) }
                        }
                    }
                    Divider()
                    Button("Quit Window Quilt") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Settings and tools")
            }
            Divider()
            if arranging {
                QuickArrangementView(manager: manager, preferences: preferences, preferredApp: navigation.preferredApp)
                    .id(arrangementID)
                Button("← Your setups") { arranging = false }.disabled(manager.openingPID != nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !runningLayouts.isEmpty {
                            Text("Open panes").font(.title2.bold())
                            ForEach(runningLayouts) { layout in
                                HStack(spacing: 8) {
                                    SetupAppIcon(bundleID: layout.record.setup.bundleID)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(layout.record.setup.name).font(.headline).lineLimit(1)
                                        Text("\(layout.windows.count) panes · \(layout.location)")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Button { manager.addPane(to: layout) } label: {
                                        Image(systemName: "plus")
                                    }
                                    .buttonStyle(QuiltButtonStyle(iconOnly: true))
                                    .accessibilityLabel("Add pane to \(layout.record.setup.name)")
                                    .help("Add one pane and rearrange this set")
                                    .disabled(layout.windows.count >= 40)
                                    Button { manager.closeAllPanes(in: layout) } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(QuiltButtonStyle(role: .destructive, iconOnly: true))
                                    .accessibilityLabel("Close all panes in \(layout.record.setup.name)")
                                    .help("Close all \(layout.windows.count) panes in this set")
                                }
                                .padding(.vertical, 8)
                                .disabled(!manager.trusted || manager.openingPID != nil)
                            }
                            Divider().padding(.vertical, 4)
                        }
                        Text("Your setups").font(.title2.bold())
                        ForEach(preferences.setups) { setup in
                            Button { manager.runSetup(setup) } label: {
                                HStack(spacing: 10) {
                                    SetupThumbnail(setup: setup).frame(width: 70, height: 48)
                                    SetupAppIcon(bundleID: setup.bundleID)
                                    Text(setup.name).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(QuiltButtonStyle(role: .quiet, isStatic: true))
                                .disabled(!manager.trusted || manager.openingPID != nil)
                        }
                        if preferences.setups.isEmpty {
                            Text("Save an arrangement to open it here in one click.").foregroundStyle(.secondary).padding(.vertical)
                        }
                    }
                }
                Button {
                    arrangementID = UUID()
                    arranging = true
                } label: { Label("New arrangement…", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(QuiltButtonStyle(role: .primary)).disabled(manager.openingPID != nil)
                if !manager.trusted {
                    Button("Grant Accessibility access…") { Accessibility.requestPermission(); openAccessibility() }
                }
                Text(manager.status).font(.caption).foregroundStyle(.secondary).lineLimit(3).help(manager.status)
                HStack {
                    if manager.openingPID != nil {
                        ProgressView().controlSize(.small)
                        Button("Stop") { manager.cancelOpening() }
                    } else {
                        Button("Undo") { manager.execute(.undo) }.disabled(manager.undoLabel == nil)
                    }
                    Spacer()
                    Button("Manage setups…") { openWindow(.layouts) }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .buttonStyle(QuiltButtonStyle()).tint(QuiltStyle.accent)
            .onChange(of: arranging) { _, value in arrangementChanged(value) }
            .onChange(of: preferences.setups.count) { _, _ in arrangementChanged(arranging) }
            .onChange(of: manager.trusted) { _, _ in arrangementChanged(arranging) }
            .onChange(of: runningLayouts.count) { _, _ in arrangementChanged(arranging) }
    }
}
