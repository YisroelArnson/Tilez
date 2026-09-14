import Foundation

public struct WindowSetup: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var bundleID: String
    public var appName: String
    public var count: Int
    public var columns: Int
    public var rows: Int
    public var gap: Double
    public var displayID: String
    public var desktop: String
    public var freshWindows: Bool
    // Optional on disk so setups saved before 1.3 still decode.
    public var preserveFullScreen: Bool?
    public var keepsFullScreen: Bool { preserveFullScreen ?? false }

    public init(name: String = "", bundleID: String = "", appName: String = "",
                count: Int = 6, columns: Int = 3, rows: Int = 2, gap: Double = 8,
                displayID: String = "", desktop: String = "new", freshWindows: Bool = false, preserveFullScreen: Bool = false) {
        self.name = name; self.bundleID = bundleID; self.appName = appName
        self.count = count; self.columns = columns; self.rows = rows; self.gap = gap
        self.displayID = displayID; self.desktop = desktop; self.freshWindows = freshWindows; self.preserveFullScreen = preserveFullScreen
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !bundleID.isEmpty
            && (1...40).contains(count) && (0...20).contains(columns) && (0...20).contains(rows)
            && gap.isFinite && (0...32).contains(gap)
    }

    public static func eligibleIDs(live: [String], initial: Set<String>, onDestination: Set<String>, fresh: Bool) -> [String] {
        live.filter { !initial.contains($0) || (!fresh && onDestination.contains($0)) }
    }
}
