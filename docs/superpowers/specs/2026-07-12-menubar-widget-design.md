# PurpleAir Bar — macOS Menu Bar Widget + PurpleAirKit Monorepo

**Date:** 2026-07-12
**Status:** Approved (user), implementation authorized

## 1. Vision

A macOS menu bar widget that shows the local PurpleAir sensor's AQI at a glance and
opens into a miniature of the iOS living wallpaper. It is a polite housemate:
near-zero CPU/IO, appears with a colored dot + number when the sensor answers,
fades to a dim ghost glyph when it doesn't, and never fights the OS (App Nap
allowed, wakeups coalesced). Apple's Weather widget cannot be extended (no API;
WeatherKit is source-locked), so this sits beside it, matching its design language.

The repo becomes a small monorepo: shared Swift code moves into a local SwiftPM
package consumed by both apps.

## 2. Monorepo restructure

```
purpleair-lan/
├── PurpleAirKit/                    # NEW — local SwiftPM package
│   ├── Package.swift                # swift-tools 6.0; platforms iOS 18, macOS 15
│   ├── Sources/PurpleAirKit/        # moved from PurpleAir LAN/, made public:
│   │   AirQuality.swift  PurpleAirData.swift  PurpleAirService.swift
│   │   PressureHistoryStore.swift  ScenePalette.swift  SolarModel.swift
│   │   AmbientSceneView.swift  AQIScaleBar.swift  ReachabilityPolicy.swift (new)
│   └── Tests/PurpleAirKitTests/     # moved: AirQuality/PurpleAirData/
│                                    # PressureHistoryStore/SceneMath tests
│                                    # + new ReachabilityPolicy tests
├── PurpleAir LAN.xcodeproj          # iOS app (stays put) — depends on PurpleAirKit
├── PurpleAir LAN/                   # iOS-only views (Dashboard, Configuration,
│                                    # MetricCard, WeatherSpinner, App)
├── PurpleAir LANTests/              # SmokeTests only (kit tests moved out)
├── PurpleAirBar/                    # NEW — macOS app sources
├── PurpleAirBar.xcodeproj           # NEW — macOS app project
└── PurpleAir.xcworkspace            # NEW — ties both projects + package
```

- `AQIScaleBar` splits out of `MetricCard.swift` into the kit (both apps use it);
  `MetricCard` itself stays iOS-only.
- Moved types gain `public` API. Kit tests run with `swift test` (no simulator).
- iOS behavior is unchanged; it just imports `PurpleAirKit`.

## 3. Mac app architecture ("PurpleAir Bar")

`LSUIElement = true` (no Dock icon). App Sandbox on, with the outgoing-network
entitlement. Deployment target macOS 15 (MeshGradient), built with Xcode 26 so the
panel gets Liquid Glass automatically. Bundle id `com.sr.PurpleAir-Bar`.

### 3.1 `ReachabilityPolicy` (in PurpleAirKit — pure, unit-tested)

A value-type state machine; the monitor executes its decisions.

```swift
public struct ReachabilityPolicy {
    public enum Phase: Equatable { case home, searching, suspended }
    public enum Event: Equatable {
        case probeSucceeded, probeFailed
        case pathSatisfied, pathUnsatisfied, pathChanged
        case slept, woke
        case kicked            // hostname changed or panel opened with stale data
    }
    public enum Action: Equatable { case probe(after: TimeInterval), idle }
    public private(set) var phase: Phase   // starts .searching
    public mutating func handle(_ event: Event) -> Action
}
```

Rules:
- `home` + success → `probe(after: 60)`. `home` + failure → retry `probe(after: 15)`;
  the 3rd consecutive failure demotes to `searching` with `probe(after: 5)`.
- `searching` + failure → exponential backoff `5·2ⁿ` capped at 300 s.
  `searching` + success → `home`, `probe(after: 60)`.
- `pathUnsatisfied` or `slept` (any phase) → `suspended`, `idle` (no timers at all).
- `suspended` + `pathSatisfied`/`woke` → `searching` (counters reset),
  `probe(after: 2.5)` (Wi-Fi re-association grace).
- `pathChanged` while not suspended → `probe(after: 1)`. `kicked` while not
  suspended → `probe(after: 0)`. Probe results arriving while `suspended` → `idle`.

### 3.2 `SensorMonitor` (mac app — thin integration shell)

Singleton `ObservableObject` (`@MainActor`), injected into both the MenuBarExtra
label and content (works around the known MenuBarExtra content-staleness bug).

- Published: `phase`, `lastData: PurpleAirData?`, `lastUpdate: Date?`.
- **Probing:** one-shot `NSBackgroundActivityScheduler` per policy action
  (`repeats = false`, `interval = action.delay`, `tolerance = 25 %`,
  `qualityOfService: .utility`) — the OS picks the cheapest wakeup moment.
- **Fetch:** shared `URLSession(.ephemeral)` — `urlCache = nil`, no cookies,
  `timeoutIntervalForRequest = 4`, `waitsForConnectivity = false` — GET
  `http://<host>/json` (2-min firmware average, ~2 KB), decode `PurpleAirData`.
- **Event sources:** `NWPathMonitor` on a `.utility` queue (satisfied/unsatisfied/
  changed — redundant updates deduped by comparing to prior status);
  `NSWorkspace` `willSleepNotification`/`didWakeNotification`; hostname
  `@AppStorage("sensorHostname")` changes; panel-open with data older than 45 s
  (that probe wrapped in `ProcessInfo.beginActivity(.userInitiated)`).
- On success: record `pressure` into the shared `PressureHistoryStore`.
- Energy contract: **zero scheduled work while suspended; one coalesced ~2 KB LAN
  fetch per minute while home; backoff-capped probes while searching; label
  re-renders only on value change; panel view exists only while open.**

### 3.3 Menu bar label

- Reachable (`.home`): 9 pt circle `NSImage` pre-tinted with the EPA category color
  (SwiftUI template-forcing workaround), 0.5 pt black-25 % ring for contrast on
  Tahoe's transparent bar, `isTemplate = false`, cached per category — followed by
  the AQI number as monospaced-digit `Text`. Example: `● 12`.
- Unreachable (`.searching`/`.suspended`): dim ghost — `aqi.medium` template
  `NSImage` pre-rendered at 45 % alpha (template + alpha adapts to menu bar
  black/white flipping), no number. The item never disappears, so Quit and
  settings stay one click away.

### 3.4 Panel (`.menuBarExtraStyle(.window)`, fixed 340 pt wide, ~440 pt tall)

Home state — a miniature of the iOS wallpaper, top to bottom:
1. Shared `AmbientSceneView(aqi:pm25:latitude:longitude:)` fills the panel
   (animates only while open; closing tears it down).
2. Caption `OUTSIDE · PURPLEAIR-AF66` (10.5 pt semibold, kerning 1.5, white 0.62).
3. Hero: AQI numeral 64 pt thin + `AQI` 15 pt light white 0.62
   (`.contentTransition(.numericText())`), category word 15 pt semibold white 0.9,
   `72° · Dew point 51°` 13 pt (tail white 0.6).
4. PM2.5 block: `2.2 µg/m³ · EPA corrected` (20 pt medium value, 11 pt caption),
   shared `AQIScaleBar`, health sentence 11 pt white 0.72.
5. Hairline divider (white 0.12), then a two-column stat row:
   `HUMIDITY  53 % Comfortable` · `PRESSURE  995.4 hPa <trend glyph>`
   (labels 10 pt semibold white 0.62, values 13 pt medium).
6. Footer (30 pt): left `Updated 8:51 PM · sensor channels agree` (10.5 pt,
   white 0.45; amber variant when a refresh failed with cached data); right —
   safari-glyph button (opens `http://<host>/` in the browser: the sensor's own
   page) and a gear `Menu`: **Launch at Login** toggle (`SMAppService.mainApp`,
   status re-read on panel appear), **Change Sensor Address…** (swaps the footer
   into an inline TextField + Save/Cancel; saving kicks the policy), divider,
   **Quit** (⌘Q).

Away state — same scene at (AQI 25, pm 0) dimmed 20 %, centered: ghost glyph,
"Looking for your PurpleAir" (15 pt semibold), "It appears automatically when this
Mac can reach purpleair.lan." (11.5 pt white 0.6), and `Last seen 8:51 PM · AQI 12`
(11 pt white 0.45) when history exists. Footer identical (gear always reachable).

Whole panel `.environment(\.colorScheme, .dark)` — the scene is always dark.

## 4. Explicitly out of scope (YAGNI)

Notification Center WidgetKit widget (15–60 min refresh budget is too coarse and
cannot react to joining the home network), Bonjour discovery (sensors don't
advertise), multi-sensor support, sparkline history, iOS app changes beyond the
package extraction.

## 5. Testing & verification

- Kit: all existing unit tests move to the package and must pass via `swift test`;
  new `ReachabilityPolicy` tests cover every transition above (home demotion after
  exactly 3 failures, backoff doubling + 300 s cap, suspend/resume, in-flight
  results during suspension, kicked-while-suspended is idle).
- iOS: `xcodebuild build` + remaining smoke test green; app behavior unchanged.
- Mac: `xcodebuild build`, launch on this Mac against the live sensor
  (`purpleair.lan`), verify label shows `● <AQI>`, panel renders, Activity
  Monitor shows ~0 % CPU at idle; unplugging from the LAN state simulated by
  pointing the hostname at `nonexistent.invalid` → ghost within 3 poll cycles.
