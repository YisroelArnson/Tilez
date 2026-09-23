import AppKit
import TilezCore

enum GridDirection {
    case left, right, up, down

    init?(keyCode: UInt16) {
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: return nil
        }
    }

    var columnDelta: Int { self == .left ? -1 : self == .right ? 1 : 0 }
    var rowDelta: Int { self == .up ? -1 : self == .down ? 1 : 0 }
    var paneEdge: PaneEdge {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .top
        case .down: return .bottom
        }
    }
}

@MainActor extension GridEditorModel {
    /// All grid directions are spatial: never wrap at a row or column boundary.
    func arrow(_ direction: GridDirection, moving: Bool = false, copying: Bool = false) {
        guard !busy else { return }
        if resizing {
            draftColumns = max(1, min(DesktopGrid.maxColumns, draftColumns + direction.columnDelta))
            draftRows = max(1, min(DesktopGrid.maxRows, draftRows + direction.rowDelta))
            return
        }
        guard !hasActiveLayer else { return }
        let source = selectedCell ?? 0
        guard grid.slots.indices.contains(source) else { return }
        let target: Int
        if grid.paneFrames != nil {
            guard let neighbor = grid.neighbor(of: source, dx: direction.columnDelta, dy: direction.rowDelta) else { return }
            target = neighbor
        } else {
            let column = source % grid.columns + direction.columnDelta
            let row = source / grid.columns + direction.rowDelta
            guard (0..<grid.columns).contains(column), (0..<grid.rows).contains(row) else { return }
            target = row * grid.columns + column
        }
        if copying || moving {
            guard grid.slots[source].app != nil else { return }
            // Copying onto the same app would only trade a live window for a new one.
            if copying && grid.slots[target].app == grid.slots[source].app { selectedCell = target; return }
            move(from: source, to: target, repeating: copying)
        } else { selectedCell = target }
    }

    private static let appPasteboardType = NSPasteboard.PasteboardType("com.yisroelarnson.tilez.grid-app")

    func copySelectedApp() {
        guard let index = selectedCell, grid.slots.indices.contains(index),
              let app = grid.slots[index].app, let data = try? JSONEncoder().encode(app) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.appPasteboardType)
        pasteboard.setString(app.name, forType: .string)
    }

    func pasteApp() {
        guard !busy, let index = selectedCell, grid.slots.indices.contains(index),
              let data = NSPasteboard.general.data(forType: Self.appPasteboardType),
              let app = try? JSONDecoder().decode(GridApp.self, from: data), !app.bundleID.isEmpty else { return }
        guard grid.slots[index].app == nil else {
            message = "Choose an empty cell to paste this app."
            isError = false
            return
        }
        assign(app)
    }

    /// Return true only when Tilez consumed the event. Text fields keep standard
    /// editing shortcuts, including Shift–Arrow and Command–Shift–Arrow selection.
    func handleKey(_ event: NSEvent, editingText: Bool) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53 { dismissLayer(); return true }
        guard !busy else { return false }

        if choosingApp || showingSaved {
            if modifiers.isEmpty {
                if event.keyCode == 125 { moveSearchSelection(1); return true }
                if event.keyCode == 126 { moveSearchSelection(-1); return true }
                if event.keyCode == 36 || event.keyCode == 76 { confirmSearchSelection(); return true }
            }
            // Preserve rapid typing while SwiftUI is transferring focus to search.
            if !editingText, modifiers.isEmpty || modifiers == .shift,
               let text = event.characters, isSearchText(text) {
                if choosingApp { search += text } else { savedSearch += text }
                return true
            }
            return false
        }
        if saving || editingText { return false }
        if resizing {
            guard modifiers.isEmpty else { return false }
            if let direction = GridDirection(keyCode: event.keyCode) { arrow(direction); return true }
            if event.keyCode == 36 || event.keyCode == 76 { confirmResize(); return true }
            if event.characters?.lowercased() == "g" { closeLayers(); return true }
            return false
        }
        if let direction = GridDirection(keyCode: event.keyCode) {
            if modifiers.isEmpty { arrow(direction); return true }
            if modifiers == .option { split(selectedCell ?? 0, toward: direction.paneEdge); return true }
            if modifiers == [.option, .shift] { merge(selectedCell ?? 0, toward: direction.paneEdge); return true }
            if modifiers == .shift { arrow(direction, moving: true); return true }
            if modifiers == [.command, .shift] { arrow(direction, copying: true); return true }
            return false
        }
        if modifiers == [.command, .shift], event.keyCode == 51 || event.keyCode == 117 {
            removeAllPanes()
            return true
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "k": addApp()
            case "z": undo()
            case "n": newGrid()
            case "s": beginSave()
            case "o": beginSaved()
            case "c": copySelectedApp()
            case "v": pasteApp()
            default: return false
            }
            return true
        }
        guard modifiers.isEmpty || modifiers == .shift else { return false }
        if modifiers.isEmpty {
            switch event.keyCode {
            case 36, 76: openGrid(); return true
            case 51, 117:
                if let index = selectedCell { removePane(index) }
                return true
            case 49: choose(selectedCell ?? 0); return true
            default: break
            }
            if event.characters?.lowercased() == "g" { beginResize(); return true }
            if let text = event.characters, let number = Int(text), (1...9).contains(number),
               grid.slots.indices.contains(number - 1) { choose(number - 1); return true }
        }
        if let text = event.characters, isSearchText(text) {
            choose(selectedCell ?? 0)
            search = text
            return true
        }
        return false
    }

    private func isSearchText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
    }
}
