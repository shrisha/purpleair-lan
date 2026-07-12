import Testing
import Foundation
@testable import PurpleAirKit

@Test func startupKickProbesImmediately() {
    var p = ReachabilityPolicy()
    #expect(p.phase == .searching)
    #expect(p.handle(.kicked) == .probe(after: 0))
}

@Test func successPromotesToHomeWithMinutePoll() {
    var p = ReachabilityPolicy()
    #expect(p.handle(.probeSucceeded) == .probe(after: 60))
    #expect(p.phase == .home)
}

@Test func homeToleratesTwoFailuresThenDemotes() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeSucceeded)
    #expect(p.handle(.probeFailed) == .probe(after: 15))
    #expect(p.phase == .home)
    #expect(p.handle(.probeFailed) == .probe(after: 15))
    #expect(p.phase == .home)
    #expect(p.handle(.probeFailed) == .probe(after: 5))   // third strike
    #expect(p.phase == .searching)
}

@Test func homeSuccessResetsFailureCount() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeSucceeded)
    _ = p.handle(.probeFailed)
    _ = p.handle(.probeSucceeded)
    _ = p.handle(.probeFailed)
    #expect(p.handle(.probeFailed) == .probe(after: 15))  // count restarted; still home
    #expect(p.phase == .home)
}

@Test func searchingBackoffDoublesAndCaps() {
    var p = ReachabilityPolicy()
    #expect(p.handle(.probeFailed) == .probe(after: 10))   // attempt 1: 5·2¹
    #expect(p.handle(.probeFailed) == .probe(after: 20))
    #expect(p.handle(.probeFailed) == .probe(after: 40))
    #expect(p.handle(.probeFailed) == .probe(after: 80))
    #expect(p.handle(.probeFailed) == .probe(after: 160))
    #expect(p.handle(.probeFailed) == .probe(after: 300))  // capped
    #expect(p.handle(.probeFailed) == .probe(after: 300))
    #expect(p.phase == .searching)
}

@Test func sleepSuspendsAndDropsInFlightResults() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeSucceeded)
    #expect(p.handle(.slept) == .idle)
    #expect(p.phase == .suspended)
    #expect(p.handle(.probeSucceeded) == .idle)   // in-flight result during suspension
    #expect(p.phase == .suspended)
    #expect(p.handle(.probeFailed) == .idle)
    #expect(p.handle(.kicked) == .idle)
    #expect(p.handle(.pathChanged) == .idle)
}

@Test func wakeResumesWithGrace() {
    var p = ReachabilityPolicy()
    _ = p.handle(.slept)
    #expect(p.handle(.woke) == .probe(after: 2.5))
    #expect(p.phase == .searching)
}

@Test func pathLossSuspendsPathGainResumes() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeSucceeded)
    #expect(p.handle(.pathUnsatisfied) == .idle)
    #expect(p.phase == .suspended)
    #expect(p.handle(.pathSatisfied) == .probe(after: 2.5))
    #expect(p.phase == .searching)
}

@Test func pathChangeProbesQuicklyWhileActive() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeSucceeded)
    #expect(p.handle(.pathChanged) == .probe(after: 1))
    #expect(p.phase == .home)
}

@Test func redundantPathSatisfiedWhileActiveIsIdle() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeSucceeded)
    #expect(p.handle(.pathSatisfied) == .idle)
    #expect(p.phase == .home)
}

@Test func recoveryFromSearchingResetsBackoff() {
    var p = ReachabilityPolicy()
    _ = p.handle(.probeFailed)              // 10
    _ = p.handle(.probeFailed)              // 20
    _ = p.handle(.probeSucceeded)           // home
    _ = p.handle(.probeFailed)
    _ = p.handle(.probeFailed)
    _ = p.handle(.probeFailed)              // demoted, probe(5)
    #expect(p.handle(.probeFailed) == .probe(after: 10))  // backoff restarted
}
