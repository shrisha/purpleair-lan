import Foundation

/// Pure state machine deciding when the menu bar app should probe the sensor.
/// The monitor feeds it events and executes the returned action; all timing
/// policy lives here so it can be unit-tested without clocks or networks.
public struct ReachabilityPolicy {
    public enum Phase: Equatable { case home, searching, suspended }

    public enum Event: Equatable {
        case probeSucceeded, probeFailed
        case pathSatisfied, pathUnsatisfied, pathChanged
        case slept, woke
        case kicked                     // hostname change / panel open / app start
    }

    public enum Action: Equatable {
        case probe(after: TimeInterval)
        case idle
    }

    public private(set) var phase: Phase = .searching
    public private(set) var consecutiveFailures = 0
    private var searchAttempts = 0

    public init() {}

    public mutating func handle(_ event: Event) -> Action {
        switch event {
        case .pathUnsatisfied, .slept:
            phase = .suspended
            return .idle

        case .pathSatisfied, .woke:
            guard phase == .suspended else { return .idle }
            phase = .searching
            consecutiveFailures = 0
            searchAttempts = 0
            return .probe(after: 2.5)   // Wi-Fi re-association grace

        case .pathChanged:
            return phase == .suspended ? .idle : .probe(after: 1)

        case .kicked:
            return phase == .suspended ? .idle : .probe(after: 0)

        case .probeSucceeded:
            guard phase != .suspended else { return .idle }
            phase = .home
            consecutiveFailures = 0
            searchAttempts = 0
            return .probe(after: 60)

        case .probeFailed:
            switch phase {
            case .suspended:
                return .idle
            case .home:
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    phase = .searching
                    searchAttempts = 0
                    return .probe(after: 5)
                }
                return .probe(after: 15)
            case .searching:
                searchAttempts += 1
                let delay = min(5 * pow(2, Double(searchAttempts)), 300)
                return .probe(after: delay)
            }
        }
    }
}
