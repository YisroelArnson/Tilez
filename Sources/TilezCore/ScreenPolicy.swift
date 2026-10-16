public enum ScreenDestination {
    public static func choose(explicit: String?, visibleGrid: String?, pointer: String?,
                              activeWindow: String?, fallback: String?, connected: Set<String>) -> String? {
        explicit ?? activeWindow ?? fallback
    }
}

public struct ScreenTransition {
    private enum Phase {
        case stable
        case changing
        case asleep(remembered: Set<String>)
        case waking(remembered: Set<String>)
    }
    private var connected: Set<String>
    private var phase = Phase.stable

    public struct Change {
        public let removed: Set<String>
        public let recover: Set<String>
    }

    public init(connected: Set<String>) { self.connected = connected }

    public var permitsRecording: Bool {
        if case .stable = phase { return true }
        return false
    }

    public mutating func sleep(remembered: Set<String>) {
        phase = .asleep(remembered: remembered)
    }

    public mutating func wake() {
        if case .asleep(let remembered) = phase { phase = .waking(remembered: remembered) }
    }

    public mutating func screensChanged() { phase = .changing }

    public mutating func settle(on current: Set<String>) -> Change? {
        let change = Change(removed: connected.subtracting(current), recover: current.subtracting(connected))
        connected = current
        phase = .stable
        return change
    }
}
