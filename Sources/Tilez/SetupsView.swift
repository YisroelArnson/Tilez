import AppKit
import SwiftUI
import TilezCore

struct SetupThumbnail: View {
    let setup: WindowSetup
    var body: some View {
        GridPreview(count: setup.count, columns: setup.columns, rows: setup.rows, gap: setup.gap,
                    displayBounds: Display.all.first { $0.id == setup.displayID }?.bounds
                        ?? Display.all.first?.bounds ?? CGRect(x: 0, y: 0, width: 1920, height: 1080))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(setup.count) windows")
    }
}

struct SetupAppIcon: View {
    let bundleID: String
    var size: CGFloat = 24
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed").frame(width: size, height: size)
        }
    }
}

struct SetupsView: View {
    @ObservedObject var manager: WindowManager
    @ObservedObject var preferences: Preferences
    @State private var editing: WindowSetup?
    @State private var creating = false
    @State private var deletedSetup: WindowSetup?
    @State private var deletedIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let deletedSetup {
                HStack {
                    Text("Deleted “\(deletedSetup.name)”").lineLimit(1)
                    Spacer()
                    Button("Undo") {
                        preferences.setups.insert(deletedSetup, at: min(deletedIndex, preferences.setups.count))
                        self.deletedSetup = nil
                    }
                }.font(.callout)
            }
            if preferences.setups.isEmpty {
                QuickArrangementView(manager: manager, preferences: preferences)
                    .frame(maxWidth: 460).frame(maxWidth: .infinity)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your setups").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Click a setup to arrange your windows.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("New arrangement…", systemImage: "plus") { creating = true }
                        .buttonStyle(TilezButtonStyle(role: .primary)).disabled(manager.openingPID != nil)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 16)], spacing: 16) {
                        ForEach(preferences.setups) { setup in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { manager.runSetup(setup) } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        SetupThumbnail(setup: setup).frame(height: 110)
                                        HStack(spacing: 10) {
                                            SetupAppIcon(bundleID: setup.bundleID)
                                            Text(setup.name).font(.headline).lineLimit(2)
                                            Spacer(minLength: 0)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Open \(setup.name)")
                                    .disabled(!manager.trusted || manager.openingPID != nil)
                                HStack {
                                    Text("\(setup.count) windows · \(desktopLabel(setup.desktop))").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Menu {
                                        Button("Edit…") { editing = setup }
                                        Button("Duplicate") { var copy = setup; copy.id = UUID(); copy.name += " copy"; manager.saveSetup(copy) }
                                        Button("Delete", role: .destructive) {
                                            deletedIndex = preferences.setups.firstIndex { $0.id == setup.id } ?? 0
                                            deletedSetup = setup
                                            preferences.setups.removeAll { $0.id == setup.id }
                                        }
                                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Options for \(setup.name)")
                                }
                            }.tilezSurface()
                        }
                    }.padding(2)
                }
            }
        }.padding(24)
        .sheet(isPresented: $creating) {
            VStack(spacing: 16) {
                QuickArrangementView(manager: manager, preferences: preferences)
                Button("Done") { creating = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 420, height: 630).tint(TilezStyle.accent)
        }
        .sheet(item: $editing) { setup in
            SetupEditor(manager: manager, initial: setup) { manager.saveSetup($0); editing = nil }
        }
    }
    private func desktopLabel(_ value: String) -> String {
        if value == "current" { return "This desktop" }
        if value == "new" { return "New desktop" }
        return manager.desktops.first { $0.id == value }?.title ?? "Desktop unavailable"
    }
}

struct SetupEditor: View {
    @ObservedObject var manager: WindowManager
    let initial: WindowSetup
    let onSave: (WindowSetup) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            QuickArrangementView(manager: manager, preferences: manager.preferences, initial: initial, editing: true, onSave: onSave)
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 420, height: 630)
            .buttonStyle(TilezButtonStyle()).tint(TilezStyle.accent)
    }
}
