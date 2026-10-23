/// Which desktops ⌃⌥X closes, and which desktop ⌃⌥D gives each workspace.
public enum DesktopPlan {
    public struct Desktop: Equatable {
        public var id: String
        public var displayID: String
        public var isCurrent: Bool
        /// Windows on this desktop alone; a window on every desktop doesn't count.
        public var windows: Int
        public init(id: String, displayID: String, isCurrent: Bool, windows: Int) {
            self.id = id; self.displayID = displayID; self.isCurrent = isCurrent; self.windows = windows
        }
    }

    /// Desktops without windows, except the one each screen shows. macOS can't close the
    /// desktop a screen is on, and each screen keeps at least one.
    public static func closable(_ desktops: [Desktop]) -> [String] {
        let screens = Dictionary(grouping: desktops, by: \.displayID)
        return desktops.filter { desktop in
            guard desktop.windows == 0, !desktop.isCurrent else { return false }
            return screens[desktop.displayID]!.contains { $0.id != desktop.id && ($0.isCurrent || $0.windows > 0) }
        }.map(\.id)
    }

    /// One screen's desktop for each workspace, in the order given; nil when it needs a new one.
    /// `windows[i]` counts workspace i's windows on each desktop. A desktop goes to the workspace
    /// with the most windows there, so the fewest windows move; a workspace with none of its own
    /// takes an empty desktop, in order, before Tilez makes another.
    public static func homes(for windows: [[String: Int]], desktops: [String], empty: Set<String>) -> [String?] {
        var homes = [String?](repeating: nil, count: windows.count)
        var claimed = Set<String>()
        let candidates = windows.indices.flatMap { workspace in
            desktops.enumerated().compactMap { position, desktop -> (workspace: Int, position: Int, desktop: String, count: Int)? in
                let count = windows[workspace][desktop] ?? 0
                return count > 0 ? (workspace, position, desktop, count) : nil
            }
        }.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.workspace != b.workspace ? a.workspace < b.workspace : a.position < b.position
        }
        for candidate in candidates where homes[candidate.workspace] == nil && !claimed.contains(candidate.desktop) {
            homes[candidate.workspace] = candidate.desktop
            claimed.insert(candidate.desktop)
        }
        var spare = desktops.filter { empty.contains($0) && !claimed.contains($0) }
        for workspace in homes.indices where homes[workspace] == nil && !spare.isEmpty {
            homes[workspace] = spare.removeFirst()
        }
        return homes
    }
}
