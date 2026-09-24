import AppKit
import ApplicationServices

/// Short eased moves for other apps' windows. Accessibility has no animation, so a move is
/// stepped at display rate: fast, but a glide instead of a jump.
@MainActor enum WindowMotion {
    nonisolated static let duration = 0.16
    private static var runs: [Int: Task<Void, Never>] = [:]

    /// Ease-out cubic: quick at first, settling into place.
    nonisolated static func eased(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }

    /// Glides `element` to `end`, replacing any move already running for it. Resolves when the
    /// window has arrived; a final write catches apps that adjust frames while settling.
    static func move(_ element: AXUIElement, to end: CGRect, duration: Double = duration) async {
        let key = Int(CFHash(element))
        runs[key]?.cancel()
        let run = Task { @MainActor in
            let start = (try? await Accessibility.perform { Accessibility.rect(element) }) ?? nil
            if let start, !reduceMotion {
                let resizes = abs(start.width - end.width) > 0.5 || abs(start.height - end.height) > 0.5
                let began = Date()
                while !Task.isCancelled {
                    let t = eased(Date().timeIntervalSince(began) / duration)
                    let frame = interpolate(start, end, t)
                    _ = try? await Accessibility.perform {
                        if resizes { Accessibility.setFrame(element, to: frame) } else { setPosition(element, frame.origin) }
                    }
                    if t >= 1 { break }
                    try? await Task.sleep(nanoseconds: 8_000_000)
                }
            }
            guard !Task.isCancelled else { return }
            _ = try? await Accessibility.perform { Accessibility.setFrame(element, to: end) }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await Accessibility.perform { Accessibility.setFrame(element, to: end) }
        }
        runs[key] = run
        await run.value
        if runs[key] == run { runs[key] = nil }
    }

    static func stop(_ element: AXUIElement) {
        runs.removeValue(forKey: Int(CFHash(element)))?.cancel()
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    nonisolated static func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    nonisolated static func setPosition(_ element: AXUIElement, _ origin: CGPoint) {
        var point = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }
}
