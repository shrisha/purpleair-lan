import SwiftUI
import Network
import PurpleAirKit

/// Thin integration shell around ReachabilityPolicy: owns the path monitor,
/// sleep/wake observers, the coalesced one-shot scheduler, and the URL session.
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
    private var scheduler: NSBackgroundActivityScheduler?
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

    /// Panel just opened: refresh if what we have is stale for a live glance.
    func panelOpened() {
        guard phase == .home else { return }
        guard let lastUpdate, Date().timeIntervalSince(lastUpdate) > 45 else { return }
        apply(.kicked)
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
        case .idle:
            scheduler?.invalidate()
            scheduler = nil
        case .probe(let delay):
            schedule(after: delay)
        }
    }

    private func schedule(after delay: TimeInterval) {
        scheduler?.invalidate()
        scheduler = nil
        guard delay > 0 else {
            Task { await self.probe() }
            return
        }
        let activity = NSBackgroundActivityScheduler(identifier: "com.sr.PurpleAir-Bar.poll")
        activity.repeats = false
        activity.interval = delay
        activity.tolerance = max(delay * 0.25, 1)   // let the OS coalesce wakeups
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor [weak self] in
                await self?.probe()
                completion(.finished)
            }
        }
        scheduler = activity
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
            apply(.probeFailed)
        }
    }
}
