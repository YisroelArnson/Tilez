public enum ScreenDestination {
    public static func choose(explicit: String?, visibleGrid: String?, pointer: String?,
                              activeWindow: String?, fallback: String?, connected: Set<String>) -> String? {
        [explicit, visibleGrid, pointer, activeWindow, fallback].compactMap { $0 }.first { connected.contains($0) }
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
        if case .asleep = phase { return }
        phase = .asleep(remembered: remembered.intersection(connected))
    }

    public mutating func wake() {
        if case .asleep(let remembered) = phase { phase = .waking(remembered: remembered) }
    }

    public mutating func screensChanged() {
        if case .stable = phase { phase = .changing }
    }

    public mutating func settle(on current: Set<String>) -> Change? {
        if case .asleep = phase { return nil }
        var recover = current.subtracting(connected)
        if case .waking(let remembered) = phase { recover.formUnion(remembered.intersection(current)) }
        let change = Change(removed: connected.subtracting(current), recover: recover)
        connected = current
        phase = .stable
        return change
    }
}
