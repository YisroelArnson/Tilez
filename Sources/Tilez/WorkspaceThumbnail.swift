import AppKit
import SwiftUI
import TilezCore

/// A workspace drawn from its data: each screen's panes in place, with each window's app icon.
/// It needs no screenshots, so it's always current.
struct WorkspaceThumbnail: View {
    let workspace: Workspace
    var height: CGFloat = 40
    var maxWidth: CGFloat = 132

    var body: some View {
        let aspects = workspace.screens.map { screen -> CGFloat in
            let bounds = Display.all.first { $0.id == screen.displayID }?.bounds ?? Display.all.first?.bounds
            return bounds.map { $0.width / max(1, $0.height) } ?? 1.6
        }
        let spacing: CGFloat = 3
        let natural = aspects.reduce(0) { $0 + $1 * height } + spacing * CGFloat(max(0, aspects.count - 1))
        let scale = min(1, maxWidth / max(1, natural))
        return HStack(spacing: spacing * scale) {
            ForEach(workspace.screens.indices, id: \.self) { index in
                screen(workspace.screens[index], size: CGSize(width: aspects[index] * height * scale, height: height * scale))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(workspace.windowCount) windows")
    }

    private func screen(_ screen: WorkspaceScreen, size: CGSize) -> some View {
        let frames = screen.grid.normalizedFrames
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.12))
            ForEach(screen.grid.slots.indices, id: \.self) { index in
                let frame = frames[index]
                let pane = CGRect(x: frame.minX * size.width + 1, y: frame.minY * size.height + 1,
                                  width: max(1, frame.width * size.width - 2), height: max(1, frame.height * size.height - 2))
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85))
                    if let app = screen.grid.slots[index].app, pane.width > 9, pane.height > 9 {
                        Image(nsImage: AppIcons.icon(for: app)).resizable().interpolation(.high)
                            .frame(width: min(18, pane.width - 3, pane.height - 3), height: min(18, pane.width - 3, pane.height - 3))
                    }
                }
                .frame(width: pane.width, height: pane.height)
                .offset(x: pane.minX, y: pane.minY)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// App icons by bundle ID, loaded once.
@MainActor enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(for app: GridApp) -> NSImage {
        if let icon = cache[app.bundleID] { return icon }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: app.name)!
        cache[app.bundleID] = icon
        return icon
    }
}
