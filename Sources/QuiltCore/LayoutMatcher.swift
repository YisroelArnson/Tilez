import Foundation

public struct WindowIdentity {
    public let app: String
    public let title: String
    public let ordinal: Int
    public init(app: String, title: String, ordinal: Int) {
        self.app = app; self.title = title; self.ordinal = ordinal
    }
}

public enum LayoutMatcher {
    // Reserve exact titles before falling back, so a missing window cannot
    // steal another saved window's exact match.
    public static func match(saved: [WindowIdentity], live: [WindowIdentity]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var used: Set<Int> = []
        for (index, record) in saved.enumerated() where !record.title.isEmpty {
            if let match = live.indices.first(where: { !used.contains($0) && live[$0].app == record.app && live[$0].title == record.title }) {
                result[index] = match; used.insert(match)
            }
        }
        for (index, record) in saved.enumerated() where result[index] == nil {
            let candidates = live.indices.filter { !used.contains($0) && live[$0].app == record.app }
            if let match = candidates.first(where: { live[$0].ordinal == record.ordinal }) ?? candidates.first {
                result[index] = match; used.insert(match)
            }
        }
        return result
    }
}
