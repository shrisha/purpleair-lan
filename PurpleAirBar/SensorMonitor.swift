import SwiftUI
import Network
import PurpleAirKit

/// Thin integration shell around ReachabilityPolicy: owns the path monitor,
/// sleep/wake observers, the tolerant one-shot poll timer, and the URL session.
/// Energy contract: zero scheduled work while suspended; one ~2 KB LAN fetch
/// per minute while home; backoff-capped probes while searching.
@MainActor
final class SensorMonitor: ObservableObject {
    static let shared = SensorMonitor()

    @Published private(set) var phase: ReachabilityPolicy.Phase = .searching
    @Published private(set) var lastData: PurpleAirData?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isStale = false

    @AppStorage("sensorHostname") var hostname: String = "purpleair.lan"

    let pressureStore = PressureHistoryStore()

    private var policy = ReachabilityPolicy()
    private var pollTimer: Timer?
    private var probeTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var lastPathStatus: NWPath.Status?
    private var started = false

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.waitsForConnectivity = false
        config.urlCache = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = path.status
            Task { @MainActor [weak self] in self?.pathUpdated(status) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.sr.PurpleAir-Bar.path", qos: .utility))

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.apply(.slept) }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.apply(.woke) }
        }

        apply(.kicked)
    }

    func hostnameDidChange() {
        lastData = nil
        lastUpdate = nil
        apply(.kicked)
    }

    /// Panel just opened: user-initiated freshness. Kick while searching (skip
    /// the backoff), or while home with stale/absent data. No-op when suspended.
    func panelOpened() {
        switch phase {
        case .suspended:
            return
        case .searching:
            apply(.kicked)
        case .home:
            guard lastUpdate.map({ Date().timeIntervalSince($0) > 45 }) ?? true else { return }
            apply(.kicked)
        }
    }

    // MARK: internals

    private func pathUpdated(_ status: NWPath.Status) {
        defer { lastPathStatus = status }
        if status == .satisfied {
            // NWPathMonitor fires redundantly; distinguish "came up" from "changed".
            apply(lastPathStatus == .satisfied ? .pathChanged : .pathSatisfied)
        } else if lastPathStatus == nil || lastPathStatus == .satisfied {
            apply(.pathUnsatisfied)
        }
    }

    private func apply(_ event: ReachabilityPolicy.Event) {
        let action = policy.handle(event)
        phase = policy.phase
        isStale = policy.phase == .home && policy.consecutiveFailures > 0
        switch action {
        case .suspend:
            pollTimer?.invalidate()
            pollTimer = nil
            probeTask?.cancel()
            probeTask = nil
        case .idle:
            break
        case .probe(let delay):
            schedule(after: delay)
        }
    }

    private func launchProbe() {
        probeTask?.cancel()
        probeTask = Task { await self.probe() }
    }

    private func schedule(after delay: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = nil
        guard delay > 0 else {
            launchProbe()
            return
        }
        // A run-loop Timer, not NSBackgroundActivityScheduler: the scheduler
        // treats the interval as a maintenance hint and defers indefinitely
        // once the system goes idle (observed 20+ min stalls). A tolerant
        // timer still coalesces wakeups but keeps a user-visible cadence.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.launchProbe()
            }
        }
        timer.tolerance = max(delay * 0.25, 1)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func probe() async {
        guard policy.phase != .suspended else { return }
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let url = URL(string: "http://\(host)/json") else {
            apply(.probeFailed)
            return
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard !Task.isCancelled, policy.phase != .suspended else { return }
            guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
                apply(.probeFailed)
                return
            }
            let decoded = try JSONDecoder().decode(PurpleAirData.self, from: data)
            lastData = decoded
            lastUpdate = Date()
            if let pressure = decoded.pressure {
                pressureStore.record(pressure)
            }
            apply(.probeSucceeded)
        } catch {
            // A cancelled probe was superseded (new kick/suspend); the superseding
            // path owns the next schedule — report nothing.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            guard policy.phase != .suspended else { return }
            apply(.probeFailed)
        }
    }
}
