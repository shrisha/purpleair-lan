import Testing
import Foundation
@testable import PurpleAirKit

private func makeStore(clock: @escaping () -> Date) -> PressureHistoryStore {
    let defaults = UserDefaults(suiteName: "pressure-test-\(UUID().uuidString)")!
    return PressureHistoryStore(defaults: defaults, now: clock)
}

@Test func trendNilWithoutHistory() {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let store = makeStore(clock: { t })
    store.record(1000)
    t += 60
    store.record(1000.5)
    #expect(store.trend == nil) // only 1 minute of history
}

@Test func risingTrend() {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let store = makeStore(clock: { t })
    store.record(1000)
    t += 3 * 3600
    store.record(1001.5)
    #expect(store.trend == .rising(rapid: false))
}

@Test func fallingRapidly() {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let store = makeStore(clock: { t })
    store.record(1004)
    t += 3 * 3600
    store.record(1000.5)
    #expect(store.trend == .falling(rapid: true))
}

@Test func steadyTrend() {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let store = makeStore(clock: { t })
    store.record(1000)
    t += 3 * 3600
    store.record(1000.4)
    #expect(store.trend == .steady)
}

@Test func prunesOldSamplesAndPersists() {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let defaults = UserDefaults(suiteName: "pressure-test-persist-\(UUID().uuidString)")!
    let store = PressureHistoryStore(defaults: defaults, now: { t })
    store.record(990)          // will fall outside the window
    t += 5 * 3600
    store.record(1000)
    t += 3 * 3600
    store.record(1002)
    // second instance reads the same defaults
    let reloaded = PressureHistoryStore(defaults: defaults, now: { t })
    #expect(reloaded.trend == .rising(rapid: false))
}
