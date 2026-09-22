import Foundation

public enum WindowInventory {
    /// Missing AX metadata on another Space is not evidence that a window is a utility.
    public static func shouldExclude(isDocument: Bool?, modal: Bool?, minimized: Bool = false) -> Bool {
        (!minimized && isDocument == false) || modal == true
    }

    /// Prefer live Accessibility records, but retain windows on other Spaces once each.
    public static func merge<Window: Identifiable>(accessible: [Window], otherDesktops: [Window]) -> [Window] {
        var seen: Set<Window.ID> = []
        return (accessible + otherDesktops).filter { seen.insert($0.id).inserted }
    }
}
