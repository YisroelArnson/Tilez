import Foundation

public enum WindowCountError: Error, Equatable {
    case invalidTarget
    case windowDidNotAppear
    case windowsKeepClosing
}

/// Waits for observable window creation rather than assuming a menu action succeeded.
@MainActor public enum WindowCount {
    public static func prepare(
        target: Int,
        current: () async throws -> [String],
        requestNew: () async throws -> Void,
        wait: () async throws -> Void,
        progress: (Int) -> Void = { _ in },
        pollsPerWindow: Int = 40
    ) async throws -> [String] {
        guard (1...40).contains(target) else { throw WindowCountError.invalidTarget }
        var windows = try await current()
        var requests = 0
        while windows.count < target {
            try Task.checkCancellation()
            // Bound work even if another process or the user keeps closing windows.
            guard requests < target else { throw WindowCountError.windowsKeepClosing }
            let before = Set(windows)
            progress(windows.count)
            try await requestNew()
            requests += 1
            var appeared = false
            for _ in 0..<max(1, pollsPerWindow) {
                try Task.checkCancellation()
                try await wait()
                try Task.checkCancellation()
                windows = try await current()
                if !Set(windows).subtracting(before).isEmpty { appeared = true; break }
            }
            guard appeared else { throw WindowCountError.windowDidNotAppear }
        }
        try Task.checkCancellation()
        progress(windows.count)
        return Array(windows.prefix(target))
    }
}
