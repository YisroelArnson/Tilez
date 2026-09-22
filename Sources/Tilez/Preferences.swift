import AppKit
import TilezCore

struct Shortcut: Codable, Equatable {
    var key: UInt32
    var modifiers: UInt32
    var label: String
}

enum Command: String, CaseIterable, Identifiable {
    case tile, undo, draw, nextDisplay, previousDisplay
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case firstThird, middleThird, lastThird, maximize, center
    var id: String { rawValue }
    var placement: Placement? { Placement(rawValue: rawValue) }
    var title: String {
        if let placement { return placement.title }
        switch self {
        case .tile: return "Tile current app"
        case .undo: return "Undo last arrangement or move"
        case .draw: return "Draw to place"
        case .nextDisplay: return "Move to next display"
        case .previousDisplay: return "Move to previous display"
        default: return rawValue
        }
    }
    var defaultShortcut: Shortcut {
        let key: UInt32
        let label: String
        switch self {
        case .tile: (key, label) = (17, "T")
        case .undo: (key, label) = (6, "Z")
        case .draw: (key, label) = (49, "Space")
        case .nextDisplay: (key, label) = (30, "]")
        case .previousDisplay: (key, label) = (33, "[")
        case .left: (key, label) = (123, "←")
        case .right: (key, label) = (124, "→")
        case .top: (key, label) = (126, "↑")
        case .bottom: (key, label) = (125, "↓")
        case .topLeft: (key, label) = (32, "U")
        case .topRight: (key, label) = (34, "I")
        case .bottomLeft: (key, label) = (38, "J")
        case .bottomRight: (key, label) = (40, "K")
        case .firstThird: (key, label) = (2, "D")
        case .middleThird: (key, label) = (3, "F")
        case .lastThird: (key, label) = (5, "G")
        case .maximize: (key, label) = (36, "Return")
        case .center: (key, label) = (8, "C")
        }
        return Shortcut(key: key, modifiers: 4096 | 2048, label: "⌃⌥\(label)")
    }
}

struct SavedWindow: Codable {
    let bundleID: String
    let title: String
    let ordinal: Int
    let displayID: String
    let normalized: CGRect
}

struct SavedLayout: Codable, Identifiable {
    var id = UUID()
    var name: String
    var windows: [SavedWindow]
    var topology: String
    var autoRestore = false
    var created = Date()
}

final class Preferences: ObservableObject {
    @Published var activeLayouts: [ActiveLayout] { didSet { save() } }
    @Published var setups: [WindowSetup] { didSet { save() } }
    @Published var desktop: String { didSet { save() } }
    @Published var preserveFullScreen: Bool { didSet { save() } }
    @Published var freshWindows: Bool { didSet { save() } }
    @Published var desiredWindows: Int { didSet { save() } }
    @Published var gap: Double { didSet { save() } }
    @Published var columns: Int { didSet { save() } }
    @Published var rows: Int { didSet { save() } }
    @Published var edgeSnap: Bool { didSet { save() } }
    @Published var titleSwipe: Bool { didSet { save() } }
    @Published var undoManual: Bool { didSet { save() } }
    @Published var gatherDisplay: String { didSet { save() } }
    @Published var shortcuts: [String: Shortcut] { didSet { save() } }
    @Published var layouts: [SavedLayout] { didSet { save() } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeLayouts = defaults.data(forKey: "activeLayouts").flatMap { try? JSONDecoder().decode([ActiveLayout].self, from: $0) } ?? []
        setups = defaults.data(forKey: "setups").flatMap { try? JSONDecoder().decode([WindowSetup].self, from: $0) } ?? []
        desktop = defaults.string(forKey: "desktop") ?? "current"
        preserveFullScreen = defaults.bool(forKey: "preserveFullScreen")
        freshWindows = defaults.bool(forKey: "freshWindows")
        desiredWindows = max(1, min(40, defaults.object(forKey: "desiredWindows") as? Int ?? 6))
        gap = defaults.object(forKey: "gap") as? Double ?? 8
        columns = defaults.integer(forKey: "columns")
        rows = defaults.integer(forKey: "rows")
        edgeSnap = defaults.object(forKey: "edgeSnap") as? Bool ?? true
        titleSwipe = defaults.bool(forKey: "titleSwipe")
        undoManual = defaults.object(forKey: "undoManual") as? Bool ?? true
        gatherDisplay = defaults.string(forKey: "gatherDisplay") ?? ""
        shortcuts = defaults.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([String: Shortcut].self, from: $0) } ?? [:]
        layouts = defaults.data(forKey: "layouts").flatMap { try? JSONDecoder().decode([SavedLayout].self, from: $0) } ?? []
    }
    func shortcut(_ command: Command) -> Shortcut { shortcuts[command.rawValue] ?? command.defaultShortcut }
    private func save() {
        defaults.set(try? JSONEncoder().encode(activeLayouts), forKey: "activeLayouts")
        defaults.set(try? JSONEncoder().encode(setups), forKey: "setups")
        defaults.set(desktop, forKey: "desktop")
        defaults.set(preserveFullScreen, forKey: "preserveFullScreen")
        defaults.set(freshWindows, forKey: "freshWindows")
        defaults.set(desiredWindows, forKey: "desiredWindows")
        defaults.set(gap, forKey: "gap")
        defaults.set(columns, forKey: "columns")
        defaults.set(rows, forKey: "rows")
        defaults.set(edgeSnap, forKey: "edgeSnap")
        defaults.set(titleSwipe, forKey: "titleSwipe")
        defaults.set(undoManual, forKey: "undoManual")
        defaults.set(gatherDisplay, forKey: "gatherDisplay")
        defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts")
        defaults.set(try? JSONEncoder().encode(layouts), forKey: "layouts")
    }
}

extension Preferences {
    func arrangementDraft() -> WindowSetup {
        WindowSetup(count: desiredWindows, columns: columns, rows: rows, gap: gap,
                    displayID: gatherDisplay, desktop: desktop, freshWindows: freshWindows,
                    preserveFullScreen: preserveFullScreen)
    }

    func useAsDefaults(_ setup: WindowSetup) {
        desiredWindows = setup.count
        columns = setup.columns
        rows = setup.rows
        gap = setup.gap
        gatherDisplay = setup.displayID
        desktop = setup.desktop
        freshWindows = setup.freshWindows
        preserveFullScreen = setup.keepsFullScreen
    }
}

