import Foundation

public enum PressureTrend: Equatable {
    case rising(rapid: Bool)
    case falling(rapid: Bool)
    case steady

    public var symbolName: String {
        switch self {
        case .rising: "arrow.up"
        case .falling: "arrow.down"
        case .steady: "equal"
        }
    }

    public var footnote: String {
        switch self {
        case .rising(true): "Rising rapidly over the last 3 hours."
        case .rising(false): "Rising over the last 3 hours."
        case .falling(true): "Falling rapidly over the last 3 hours."
        case .falling(false): "Falling over the last 3 hours."
        case .steady: "Steady over the last 3 hours."
        }
    }
}

/// Persists recent barometric samples and derives the 3-hour trend
/// (meteorological convention: ±1 hPa/3 h = rising/falling, ±3 = rapidly).
public final class PressureHistoryStore {
    private struct Sample: Codable {
        let date: Date
        let hPa: Double
    }

    private static let storageKey = "pressureHistorySamples"
    private static let window: TimeInterval = 3.5 * 3600
    private static let trendSpan: TimeInterval = 3 * 3600
    private static let minimumSpan: TimeInterval = 2 * 3600

    private let defaults: UserDefaults
    private let now: () -> Date
    private var samples: [Sample]

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Sample].self, from: data) {
            samples = decoded
        } else {
            samples = []
        }
    }

    public func record(_ hPa: Double) {
        let cutoff = now().addingTimeInterval(-Self.window)
        samples.append(Sample(date: now(), hPa: hPa))
        samples.removeAll { $0.date < cutoff }
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    public var trend: PressureTrend? {
        guard let latest = samples.last else { return nil }
        let target = latest.date.addingTimeInterval(-Self.trendSpan)
        // reference = sample closest to 3 h ago; needs ≥2 h of real span
        guard let reference = samples.min(by: {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }), latest.date.timeIntervalSince(reference.date) >= Self.minimumSpan else { return nil }

        let delta = latest.hPa - reference.hPa
        let rapid = abs(delta) >= 3
        if delta >= 1 { return .rising(rapid: rapid) }
        if delta <= -1 { return .falling(rapid: rapid) }
        return .steady
    }
}
