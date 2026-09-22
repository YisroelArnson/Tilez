import Foundation

/// Verify asynchronous AX placements without delaying already-settled windows.
@MainActor public enum WindowSettling {
    public static func finish<Window>(pending: () async throws -> [Window],
                                      retry: (Window) async throws -> Void,
                                      wait: () async throws -> Void) async throws -> [Window] {
        try Task.checkCancellation()
        var remaining = try await pending()
        for attempt in 0..<16 {
            if remaining.isEmpty { return [] }
            try await wait()
            try Task.checkCancellation()
            remaining = try await pending()
            if [2, 5, 9, 13].contains(attempt) {
                for window in remaining {
                    try Task.checkCancellation()
                    try await retry(window)
                }
            }
        }
        return remaining
    }
}
