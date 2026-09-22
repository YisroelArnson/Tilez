import Foundation

/// A running set owns exact window identities, never a title or an app-wide match.
public struct ActiveLayout: Codable, Identifiable, Equatable {
    public var id: UUID
    public var processSession: String
    public var windowIDs: [String]
    public var setup: WindowSetup
    public init(id: UUID = UUID(), processSession: String, windowIDs: [String], setup: WindowSetup) {
        self.id = id; self.processSession = processSession
        self.windowIDs = Array(NSOrderedSet(array: windowIDs)) as? [String] ?? []
        self.setup = setup
    }
}

public enum ActiveLayouts {
    /// A process launch identity prevents saved window numbers matching a restarted app.
    public static func reconcile(_ records: [ActiveLayout], live: [String: Set<String>]) -> [ActiveLayout] {
        var claimed = Set<String>()
        return records.compactMap { record in
            var next = record
            let available = live[record.processSession] ?? []
            next.windowIDs = record.windowIDs.filter { available.contains($0) && claimed.insert($0).inserted }
            return next.windowIDs.isEmpty ? nil : next
        }
    }
    public static func recording(_ record: ActiveLayout, in records: [ActiveLayout]) -> [ActiveLayout] {
        let owned = Set(record.windowIDs)
        var result: [ActiveLayout] = []
        var replaced = false
        for previous in records {
            if previous.id == record.id {
                replaced = true
                if !record.windowIDs.isEmpty { result.append(record) }
            } else {
                var next = previous
                next.windowIDs.removeAll { owned.contains($0) }
                if !next.windowIDs.isEmpty { result.append(next) }
            }
        }
        if !replaced && !record.windowIDs.isEmpty { result.append(record) }
        return result
    }
    /// Existing windows outside this set cannot be borrowed when increasing its count.
    public static func eligible(live: [String], initial: Set<String>, members: Set<String>) -> [String] {
        live.filter { members.contains($0) || !initial.contains($0) }
    }
    public static func closing(members: [String], keeping: Set<String>) -> [String] {
        members.filter { !keeping.contains($0) }
    }
}
