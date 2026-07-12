# Living-Wallpaper Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four-tile dashboard with a full-bleed ambient scene (iOS Weather design language) whose palette, haze, and numerals are driven by EPA-corrected sensor metrics, per `docs/superpowers/specs/2026-07-11-wallpaper-dashboard-design.md`.

**Architecture:** Pure-logic layer first (`AirQuality` corrections/AQI, `SolarModel`, `ScenePalette`, `PressureHistoryStore`) with unit tests, then visual layer (`AmbientSceneView` MeshGradient+Canvas, frosted `MetricCard`s), then a rewritten `DashboardView` that composes them and adds ambient behavior (idle-timer off, fading chrome).

**Tech Stack:** SwiftUI (iOS 18.5 target — `MeshGradient` available), Swift Testing (`import Testing`) for unit tests, no external dependencies.

## Global Constraints

- Project: `PurpleAir LAN.xcodeproj`, scheme `PurpleAir LAN`, simulator destination `platform=iOS Simulator,name=iPhone 17 Pro`.
- App module name for `@testable import` is `PurpleAir_LAN` (space becomes underscore).
- The pbxproj uses **filesystem-synchronized groups** (objectVersion 77): files added on disk under `PurpleAir LAN/` are picked up automatically by the app target; the test target gets its own synchronized folder in Task 1.
- All user-visible numbers use corrected values: temperature −8 °F, humidity +4 % (clamped ≤100), dew point recomputed via Magnus, PM2.5 through the EPA piecewise correction, AQI from May-2024 breakpoints. Never display firmware `pm2.5_aqi_b`.
- EPA category colors (exact): Good `#00E400`, Moderate `#FFFF00`, USG `#FF7E00`, Unhealthy `#FF0000`, Very Unhealthy `#8F3F97`, Hazardous `#7E0023`.
- Whole dashboard renders with `.environment(\.colorScheme, .dark)`; text is white with opacity hierarchy (1.0 / 0.62 secondary / 0.45 captions).
- Cards: `RoundedRectangle(cornerRadius: 22, style: .continuous)`, `.ultraThinMaterial`, 0.5 pt `white.opacity(0.14)` inner stroke, 8 pt grid gap, 16 pt outer margins.
- Every task ends with a commit ending in `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Build check command (used in several tasks):
  `xcodebuild -project "PurpleAir LAN.xcodeproj" -scheme "PurpleAir LAN" -sdk iphonesimulator -configuration Debug build 2>&1 | tail -3` → expect `** BUILD SUCCEEDED **`.
- Test command (used in several tasks):
  `xcodebuild test -project "PurpleAir LAN.xcodeproj" -scheme "PurpleAir LAN" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'PurpleAir LANTests' 2>&1 | tail -8` → expect `** TEST SUCCEEDED **`. (If xcodebuild reports the target is not in the scheme's test action, run once without `-only-testing`.)

---

### Task 1: Wire the unit-test target to a synchronized source folder

The `PurpleAir LANTests` target exists in the pbxproj but has no source folder on disk and no `fileSystemSynchronizedGroups`, so nothing compiles into it. Give it one, prove it with a smoke test.

**Files:**
- Create: `PurpleAir LANTests/SmokeTests.swift`
- Modify: `PurpleAir LAN.xcodeproj/project.pbxproj` (three small edits)

**Interfaces:**
- Consumes: nothing.
- Produces: a working `PurpleAir LANTests` target; later tasks drop `*.swift` test files into `PurpleAir LANTests/` and they compile automatically.

- [ ] **Step 1: Create the test folder and smoke test**

```swift
// PurpleAir LANTests/SmokeTests.swift
import Testing
@testable import PurpleAir_LAN

@Test func smokeTestTargetIsWired() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 2: Add a synchronized root group to the pbxproj**

In `PurpleAir LAN.xcodeproj/project.pbxproj`, find the `PBXFileSystemSynchronizedRootGroup` section (around line 37) and add a second entry so the section reads:

```
/* Begin PBXFileSystemSynchronizedRootGroup section */
		9D8B08992E405EBB00541770 /* PurpleAir LAN */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = "PurpleAir LAN";
			sourceTree = "<group>";
		};
		AA00000000000000000TESTS /* PurpleAir LANTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = "PurpleAir LANTests";
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */
```

Note: the ID must be 24 hex characters — use `AA0000000000000000000001` (the literal above with `TESTS` is NOT valid hex; use `AA0000000000000000000001` in both this step and steps 3–4).

- [ ] **Step 3: Add the group to the main group's children**

In the root `PBXGroup` (ID `9D8B088E2E405EBB00541770`, around line 70), add the new child after the app group:

```
			children = (
				9D8B08992E405EBB00541770 /* PurpleAir LAN */,
				AA0000000000000000000001 /* PurpleAir LANTests */,
				9D8B08982E405EBB00541770 /* Products */,
				9D8B08FD2E407FE800541770 /* README.md */,
			);
```

- [ ] **Step 4: Attach the group to the test target**

In `PBXNativeTarget` `9D8B08A32E405EBD00541770 /* PurpleAir LANTests */`, add a `fileSystemSynchronizedGroups` entry after `dependencies` (mirroring how the app target declares its group):

```
			dependencies = (
				9D8B08A62E405EBD00541770 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000001 /* PurpleAir LANTests */,
			);
```

- [ ] **Step 5: Run the smoke test**

Run the Global Constraints test command. Expected: `** TEST SUCCEEDED **` with 1 test passing. If xcodebuild errors on pbxproj parsing, re-check the three edits (IDs must match exactly, 24 hex chars).

- [ ] **Step 6: Commit**

```bash
git add "PurpleAir LANTests/SmokeTests.swift" "PurpleAir LAN.xcodeproj/project.pbxproj"
git commit -m "test: wire unit-test target to synchronized source folder"
```

---

### Task 2: `AirQuality` — corrections, AQI, categories (pure logic + tests)

**Files:**
- Create: `PurpleAir LAN/Models/AirQuality.swift`
- Test: `PurpleAir LANTests/AirQualityTests.swift`

**Interfaces:**
- Consumes: nothing (pure functions, `import SwiftUI` for `Color` only).
- Produces (exact, used by Tasks 3, 7, 8):

```swift
enum AQICategory: Int, CaseIterable {
    case good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous
    var name: String
    var epaColor: Color
    var healthGuidance: String
}
struct AQIReading: Equatable {
    let aqi: Int
    let category: AQICategory
    let correctedPM25: Double
    let channelsAgree: Bool
}
enum AirQuality {
    static func epaCorrectedPM25(rawCF1: Double, humidity: Double) -> Double
    static func aqi(fromCorrectedPM25: Double) -> Int
    static func category(forAQI: Int) -> AQICategory
    static func channelsAgree(_ a: Double, _ b: Double) -> Bool
    static func reading(pmA: Double, pmB: Double?, rawHumidity: Double) -> AQIReading
    static func displayTemperatureF(rawF: Double) -> Double
    static func displayHumidity(raw: Double) -> Double
    static func dewPointF(temperatureF: Double, humidity: Double) -> Double
    static func comfortDescription(humidity: Double) -> String
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// PurpleAir LANTests/AirQualityTests.swift
import Testing
import Foundation
@testable import PurpleAir_LAN

// MARK: May-2024 EPA breakpoints
@Test func aqiGoodUpperEdge() { #expect(AirQuality.aqi(fromCorrectedPM25: 9.0) == 50) }
@Test func aqiTruncatesToTenth() { #expect(AirQuality.aqi(fromCorrectedPM25: 9.05) == 50) }
@Test func aqiModerateLowerEdge() { #expect(AirQuality.aqi(fromCorrectedPM25: 9.1) == 51) }
@Test func aqiModerateUpperEdge() { #expect(AirQuality.aqi(fromCorrectedPM25: 35.4) == 100) }
@Test func aqiUnhealthyBand() { #expect(AirQuality.aqi(fromCorrectedPM25: 55.5) == 151) }
@Test func aqiCapsAt500() {
    #expect(AirQuality.aqi(fromCorrectedPM25: 325.4) == 500)
    #expect(AirQuality.aqi(fromCorrectedPM25: 400) == 500)
}
@Test func aqiNegativeClampsToZero() { #expect(AirQuality.aqi(fromCorrectedPM25: -3) == 0) }

// MARK: EPA/Barkjohn correction
@Test func correctionBaseEquation() {
    // 0.524*5 - 0.0862*41 + 5.75 = 4.8358
    #expect(abs(AirQuality.epaCorrectedPM25(rawCF1: 5.0, humidity: 41) - 4.8358) < 0.001)
}
@Test func correctionContinuousAtSeam30() {
    let below = AirQuality.epaCorrectedPM25(rawCF1: 29.999, humidity: 50)
    let above = AirQuality.epaCorrectedPM25(rawCF1: 30.001, humidity: 50)
    #expect(abs(below - above) < 0.01)
}
@Test func correctionContinuousAtSeam50() {
    let below = AirQuality.epaCorrectedPM25(rawCF1: 49.999, humidity: 50)
    let above = AirQuality.epaCorrectedPM25(rawCF1: 50.001, humidity: 50)
    #expect(abs(below - above) < 0.01)
}
@Test func correctionContinuousAtSeam210() {
    let below = AirQuality.epaCorrectedPM25(rawCF1: 209.999, humidity: 50)
    let above = AirQuality.epaCorrectedPM25(rawCF1: 210.001, humidity: 50)
    #expect(abs(below - above) < 0.01)
}
@Test func correctionContinuousAtSeam260() {
    let below = AirQuality.epaCorrectedPM25(rawCF1: 259.999, humidity: 50)
    let above = AirQuality.epaCorrectedPM25(rawCF1: 260.001, humidity: 50)
    #expect(abs(below - above) < 0.01)
}
@Test func correctionHighSmokeQuadratic() {
    // 2.966 + 0.69*300 + 8.84e-4*300^2 = 2.966 + 207 + 79.56 = 289.526
    #expect(abs(AirQuality.epaCorrectedPM25(rawCF1: 300, humidity: 30) - 289.526) < 0.01)
}
@Test func correctionNeverNegative() {
    #expect(AirQuality.epaCorrectedPM25(rawCF1: 0, humidity: 100) == 0)
}

// MARK: channel QC (EPA: agree if |A-B| < 5 µg/m³ OR relative diff < 70 %)
@Test func channelsAgreeSmallAbsoluteDiff() { #expect(AirQuality.channelsAgree(5, 9)) }
@Test func channelsAgreeSmallRelativeDiff() { #expect(AirQuality.channelsAgree(10, 20)) }
@Test func channelsDisagree() { #expect(!AirQuality.channelsAgree(1, 8) == false || !AirQuality.channelsAgree(1, 8)) }

// MARK: merged reading
@Test func readingAveragesChannels() {
    let r = AirQuality.reading(pmA: 10, pmB: 20, rawHumidity: 50)
    // mean 15 -> 0.524*15 - 0.0862*50 + 5.75 = 9.3
    #expect(abs(r.correctedPM25 - 9.3) < 0.001)
    #expect(r.aqi == 51)
    #expect(r.category == .moderate)
    #expect(r.channelsAgree)
}
@Test func readingSingleChannel() {
    let r = AirQuality.reading(pmA: 10, pmB: nil, rawHumidity: 50)
    #expect(abs(r.correctedPM25 - (0.524 * 10 - 0.0862 * 50 + 5.75)) < 0.001)
    #expect(r.channelsAgree)
}

// MARK: display corrections
@Test func temperatureCorrection() { #expect(AirQuality.displayTemperatureF(rawF: 84) == 76) }
@Test func humidityCorrectionClamps() {
    #expect(AirQuality.displayHumidity(raw: 41) == 45)
    #expect(AirQuality.displayHumidity(raw: 98) == 100)
}
@Test func dewPointMagnus() {
    // 76°F / 45 % RH -> ≈ 53 °F
    let dp = AirQuality.dewPointF(temperatureF: 76, humidity: 45)
    #expect(abs(dp - 53) < 1.5)
}
@Test func comfortBands() {
    #expect(AirQuality.comfortDescription(humidity: 20) == "Dry")
    #expect(AirQuality.comfortDescription(humidity: 45) == "Comfortable")
    #expect(AirQuality.comfortDescription(humidity: 75) == "Humid")
}

// MARK: categories
@Test func categoryBoundaries() {
    #expect(AirQuality.category(forAQI: 50) == .good)
    #expect(AirQuality.category(forAQI: 51) == .moderate)
    #expect(AirQuality.category(forAQI: 150) == .unhealthySensitive)
    #expect(AirQuality.category(forAQI: 301) == .hazardous)
}
```

Note: fix `channelsDisagree` to the intended single assertion: `#expect(AirQuality.channelsAgree(1, 8) == false)`.

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: compile FAILURE — `cannot find 'AirQuality' in scope`.

- [ ] **Step 3: Implement `AirQuality`**

```swift
// PurpleAir LAN/Models/AirQuality.swift
import SwiftUI

/// EPA AQI category per the May-2024 PM2.5 breakpoints.
enum AQICategory: Int, CaseIterable {
    case good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous

    var name: String {
        switch self {
        case .good: "Good"
        case .moderate: "Moderate"
        case .unhealthySensitive: "Unhealthy for Sensitive Groups"
        case .unhealthy: "Unhealthy"
        case .veryUnhealthy: "Very Unhealthy"
        case .hazardous: "Hazardous"
        }
    }

    /// Official EPA/AirNow category colors.
    var epaColor: Color {
        switch self {
        case .good: Color(red: 0 / 255, green: 228 / 255, blue: 0 / 255)
        case .moderate: Color(red: 255 / 255, green: 255 / 255, blue: 0 / 255)
        case .unhealthySensitive: Color(red: 255 / 255, green: 126 / 255, blue: 0 / 255)
        case .unhealthy: Color(red: 255 / 255, green: 0 / 255, blue: 0 / 255)
        case .veryUnhealthy: Color(red: 143 / 255, green: 63 / 255, blue: 151 / 255)
        case .hazardous: Color(red: 126 / 255, green: 0 / 255, blue: 35 / 255)
        }
    }

    var healthGuidance: String {
        switch self {
        case .good: "Air quality is satisfactory, and poses little or no risk."
        case .moderate: "Acceptable air. Unusually sensitive people should consider limiting prolonged exertion."
        case .unhealthySensitive: "Sensitive groups may experience health effects. The general public is less likely to be affected."
        case .unhealthy: "Some of the general public may experience health effects; sensitive groups more seriously."
        case .veryUnhealthy: "Health alert: the risk of health effects is increased for everyone."
        case .hazardous: "Health warning of emergency conditions: everyone is more likely to be affected."
        }
    }
}

/// A fully derived air-quality reading: EPA-corrected concentration + AQI.
struct AQIReading: Equatable {
    let aqi: Int
    let category: AQICategory
    let correctedPM25: Double
    let channelsAgree: Bool
}

enum AirQuality {
    // MARK: AQI (EPA May-2024 PM2.5 breakpoints)

    private static let breakpoints: [(cLo: Double, cHi: Double, aLo: Double, aHi: Double)] = [
        (0.0, 9.0, 0, 50),
        (9.1, 35.4, 51, 100),
        (35.5, 55.4, 101, 150),
        (55.5, 125.4, 151, 200),
        (125.5, 225.4, 201, 300),
        (225.5, 325.4, 301, 500),
    ]

    static func aqi(fromCorrectedPM25 concentration: Double) -> Int {
        let c = (max(concentration, 0) * 10).rounded(.down) / 10 // EPA: truncate to 0.1
        guard let bp = breakpoints.first(where: { c <= $0.cHi }) else { return 500 }
        let value = (bp.aHi - bp.aLo) / (bp.cHi - bp.cLo) * (c - bp.cLo) + bp.aLo
        return min(Int(value.rounded()), 500)
    }

    static func category(forAQI aqi: Int) -> AQICategory {
        switch aqi {
        case ...50: .good
        case ...100: .moderate
        case ...150: .unhealthySensitive
        case ...200: .unhealthy
        case ...300: .veryUnhealthy
        default: .hazardous
        }
    }

    // MARK: EPA (Barkjohn 2021 + Fire & Smoke Map extension) correction

    static func epaCorrectedPM25(rawCF1 pa: Double, humidity: Double) -> Double {
        let rh = min(max(humidity, 0), 100)
        let corrected: Double
        switch pa {
        case ..<30:
            corrected = 0.524 * pa - 0.0862 * rh + 5.75
        case ..<50:
            let w = pa / 20 - 1.5
            corrected = (0.786 * w + 0.524 * (1 - w)) * pa - 0.0862 * rh + 5.75
        case ..<210:
            corrected = 0.786 * pa - 0.0862 * rh + 5.75
        case ..<260:
            let w = pa / 50 - 4.2
            corrected = (0.69 * w + 0.786 * (1 - w)) * pa - 0.0862 * rh * (1 - w)
                + 2.966 * w + 5.75 * (1 - w) + 8.84e-4 * pa * pa * w
        default:
            corrected = 2.966 + 0.69 * pa + 8.84e-4 * pa * pa
        }
        return max(corrected, 0)
    }

    // MARK: channel QC (EPA Fire & Smoke Map rule)

    static func channelsAgree(_ a: Double, _ b: Double) -> Bool {
        let diff = abs(a - b)
        if diff < 5 { return true }
        let mean = (a + b) / 2
        return mean > 0 && diff / mean < 0.7
    }

    static func reading(pmA: Double, pmB: Double?, rawHumidity: Double) -> AQIReading {
        let merged: Double
        let agree: Bool
        if let pmB {
            merged = (pmA + pmB) / 2
            agree = channelsAgree(pmA, pmB)
        } else {
            merged = pmA
            agree = true
        }
        let corrected = epaCorrectedPM25(rawCF1: merged, humidity: rawHumidity)
        let aqiValue = aqi(fromCorrectedPM25: corrected)
        return AQIReading(
            aqi: aqiValue,
            category: category(forAQI: aqiValue),
            correctedPM25: corrected,
            channelsAgree: agree
        )
    }

    // MARK: display corrections (sensor self-heating biases)

    static func displayTemperatureF(rawF: Double) -> Double { rawF - 8 }

    static func displayHumidity(raw: Double) -> Double { min(raw + 4, 100) }

    /// Magnus formula; inputs are the *corrected* display temperature/humidity.
    static func dewPointF(temperatureF: Double, humidity: Double) -> Double {
        let t = (temperatureF - 32) / 1.8
        let rh = min(max(humidity, 1), 100)
        let gamma = log(rh / 100) + 17.625 * t / (243.04 + t)
        let dewC = 243.04 * gamma / (17.625 - gamma)
        return dewC * 1.8 + 32
    }

    static func comfortDescription(humidity: Double) -> String {
        switch humidity {
        case ..<30: "Dry"
        case ...60: "Comfortable"
        default: "Humid"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`, all AirQuality tests passing.

- [ ] **Step 5: Commit**

```bash
git add "PurpleAir LAN/Models/AirQuality.swift" "PurpleAir LANTests/AirQualityTests.swift"
git commit -m "feat: EPA-corrected PM2.5, May-2024 AQI, display corrections"
```

---

### Task 3: Decode new sensor fields + derived display properties + endpoint switch

**Files:**
- Modify: `PurpleAir LAN/Models/PurpleAirData.swift`
- Modify: `PurpleAir LAN/Services/PurpleAirService.swift` (constructAPIURL, ~line 114)
- Test: `PurpleAir LANTests/PurpleAirDataTests.swift`

**Interfaces:**
- Consumes: `AirQuality`, `AQIReading` from Task 2.
- Produces (used by Task 8):

```swift
// new stored properties on PurpleAirData
let pm25CF1A: Double?    // "pm2_5_cf_1"
let pm25CF1B: Double?    // "pm2_5_cf_1_b"
let latitude: Double?    // "lat"
let longitude: Double?   // "lon"
// new computed properties
var airQualityReading: AQIReading?   // nil when pm2_5_cf_1 missing
var displayTemperatureF: Double?     // corrected (-8)
var displayHumidityPct: Double?      // corrected (+4, ≤100)
var displayDewPointF: Double?        // Magnus from the corrected pair
```

- [ ] **Step 1: Write the failing tests**

```swift
// PurpleAir LANTests/PurpleAirDataTests.swift
import Testing
import Foundation
@testable import PurpleAir_LAN

private let fixtureJSON = """
{
  "SensorId": "48:3f:da:2a:af:66",
  "Geo": "PurpleAir-af66",
  "place": "outside",
  "lat": 37.238899,
  "lon": -122.002502,
  "current_temp_f": 84,
  "current_humidity": 41,
  "current_dewpoint_f": 58,
  "pressure": 994.61,
  "pm2_5_cf_1": 5.0,
  "pm2_5_cf_1_b": 6.0,
  "pm2.5_aqi_b": 8,
  "p25aqic_b": "rgb(87,187,10)",
  "rssi": -57,
  "uptime": 212854,
  "version": "7.02"
}
""".data(using: .utf8)!

@Test func decodesNewFields() throws {
    let data = try JSONDecoder().decode(PurpleAirData.self, from: fixtureJSON)
    #expect(data.pm25CF1A == 5.0)
    #expect(data.pm25CF1B == 6.0)
    #expect(data.latitude == 37.238899)
    #expect(data.longitude == -122.002502)
}

@Test func derivedReadingUsesCorrectedPipeline() throws {
    let data = try JSONDecoder().decode(PurpleAirData.self, from: fixtureJSON)
    let r = try #require(data.airQualityReading)
    // mean(5,6)=5.5 -> 0.524*5.5 - 0.0862*41 + 5.75 = 5.0978 -> AQI 28
    #expect(abs(r.correctedPM25 - 5.0978) < 0.001)
    #expect(r.aqi == 28)
    #expect(r.category == .good)
    #expect(r.channelsAgree)
}

@Test func derivedDisplayValues() throws {
    let data = try JSONDecoder().decode(PurpleAirData.self, from: fixtureJSON)
    #expect(data.displayTemperatureF == 76)
    #expect(data.displayHumidityPct == 45)
    let dp = try #require(data.displayDewPointF)
    #expect(abs(dp - 53) < 1.5)
}

@Test func readingNilWithoutPMField() throws {
    let json = #"{"SensorId":"x","current_humidity":40}"#.data(using: .utf8)!
    let data = try JSONDecoder().decode(PurpleAirData.self, from: json)
    #expect(data.airQualityReading == nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: compile FAILURE — `value of type 'PurpleAirData' has no member 'pm25CF1A'`.

- [ ] **Step 3: Extend `PurpleAirData`**

In `PurpleAir LAN/Models/PurpleAirData.swift`, add the stored properties to the struct (after `p25AqicB`):

```swift
    // Raw PM2.5 (CF=1) per laser channel — inputs to the EPA correction
    let pm25CF1A: Double?
    let pm25CF1B: Double?

    // Sensor location (drives the solar model)
    let latitude: Double?
    let longitude: Double?
```

Add to `CodingKeys`:

```swift
        case pm25CF1A = "pm2_5_cf_1"
        case pm25CF1B = "pm2_5_cf_1_b"
        case latitude = "lat"
        case longitude = "lon"
```

Add a new extension at the end of the file:

```swift
// MARK: - Corrected display values
extension PurpleAirData {
    /// EPA-corrected reading from the A/B channel mean. Nil when the sensor
    /// reports no PM data at all.
    var airQualityReading: AQIReading? {
        guard let a = pm25CF1A else { return nil }
        return AirQuality.reading(pmA: a, pmB: pm25CF1B, rawHumidity: currentHumidity ?? 50)
    }

    /// Board self-heating makes the raw temperature read ~8 °F high.
    var displayTemperatureF: Double? {
        currentTempF.map(AirQuality.displayTemperatureF(rawF:))
    }

    /// Raw humidity reads ~4 % dry.
    var displayHumidityPct: Double? {
        currentHumidity.map(AirQuality.displayHumidity(raw:))
    }

    /// Dew point recomputed from the corrected pair (the sensor's own
    /// current_dewpoint_f is derived from the biased raw values).
    var displayDewPointF: Double? {
        guard let t = displayTemperatureF, let h = displayHumidityPct else { return nil }
        return AirQuality.dewPointF(temperatureF: t, humidity: h)
    }
}
```

- [ ] **Step 4: Switch the dashboard fetch to the 2-minute average endpoint**

In `PurpleAir LAN/Services/PurpleAirService.swift`, `constructAPIURL` (~line 114), change:

```swift
        let urlString = "http://\(cleanHostname)/json?live=true"
```

to:

```swift
        // Firmware's 2-minute average — the right smoothing for an ambient display
        let urlString = "http://\(cleanHostname)/json"
```

- [ ] **Step 5: Run tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add "PurpleAir LAN/Models/PurpleAirData.swift" "PurpleAir LAN/Services/PurpleAirService.swift" "PurpleAir LANTests/PurpleAirDataTests.swift"
git commit -m "feat: decode raw PM channels + location, derive corrected display values"
```

---

### Task 4: `PressureHistoryStore` — persisted samples + 3-hour trend

**Files:**
- Create: `PurpleAir LAN/Services/PressureHistoryStore.swift`
- Test: `PurpleAir LANTests/PressureHistoryStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Tasks 7, 8):

```swift
enum PressureTrend: Equatable {
    case rising(rapid: Bool), falling(rapid: Bool), steady
    var symbolName: String   // "arrow.up" / "arrow.down" / "equal"
    var footnote: String     // "Rising over the last 3 hours." etc.
}
final class PressureHistoryStore {
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init)
    func record(_ hPa: Double)
    var trend: PressureTrend?   // nil until ≥2 h of history
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// PurpleAir LANTests/PressureHistoryStoreTests.swift
import Testing
import Foundation
@testable import PurpleAir_LAN

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: compile FAILURE — `cannot find 'PressureHistoryStore' in scope`.

- [ ] **Step 3: Implement**

```swift
// PurpleAir LAN/Services/PressureHistoryStore.swift
import Foundation

enum PressureTrend: Equatable {
    case rising(rapid: Bool)
    case falling(rapid: Bool)
    case steady

    var symbolName: String {
        switch self {
        case .rising: "arrow.up"
        case .falling: "arrow.down"
        case .steady: "equal"
        }
    }

    var footnote: String {
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
final class PressureHistoryStore {
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

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([Sample].self, from: data) {
            samples = decoded
        } else {
            samples = []
        }
    }

    func record(_ hPa: Double) {
        let cutoff = now().addingTimeInterval(-Self.window)
        samples.append(Sample(date: now(), hPa: hPa))
        samples.removeAll { $0.date < cutoff }
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    var trend: PressureTrend? {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add "PurpleAir LAN/Services/PressureHistoryStore.swift" "PurpleAir LANTests/PressureHistoryStoreTests.swift"
git commit -m "feat: persisted pressure history with 3-hour trend"
```

---

### Task 5: `ScenePalette` + `SolarModel` — the scene's color math (pure + tests)

**Files:**
- Create: `PurpleAir LAN/Views/Scene/ScenePalette.swift`
- Create: `PurpleAir LAN/Views/Scene/SolarModel.swift`
- Test: `PurpleAir LANTests/SceneMathTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Task 6):

```swift
struct RGB: Equatable {           // 0…1 components
    let r: Double; let g: Double; let b: Double
    init(hex: UInt32)
    func mixed(with other: RGB, amount: Double) -> RGB
    var color: Color
}
enum ScenePalette {
    // 4 gradient anchors [top, upper, lower, horizon], continuous in AQI
    static func anchors(aqi: Double, daylight: Double, twilight: Double) -> [RGB]
    // 9 colors, row-major 3×3, for MeshGradient
    static func meshColors(aqi: Double, daylight: Double, twilight: Double) -> [Color]
}
enum SolarModel {
    // daylight: 0 night … 1 midday; twilight: peaks when sun crosses horizon
    static func factors(date: Date, latitude: Double?, longitude: Double?) -> (daylight: Double, twilight: Double)
    static func solarElevationDegrees(date: Date, latitude: Double, longitude: Double) -> Double
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// PurpleAir LANTests/SceneMathTests.swift
import Testing
import Foundation
@testable import PurpleAir_LAN

private func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

// Saratoga, CA: lat 37.24, lon -122.0. Local noon PDT ≈ 19:00 UTC.
@Test func solarElevationHighAtLocalNoonInJuly() {
    let elev = SolarModel.solarElevationDegrees(date: utcDate(2026, 7, 11, 19), latitude: 37.24, longitude: -122.0)
    #expect(elev > 60)
}

@Test func solarElevationNegativeAtLocalMidnight() {
    let elev = SolarModel.solarElevationDegrees(date: utcDate(2026, 7, 11, 7), latitude: 37.24, longitude: -122.0)
    #expect(elev < -10)
}

@Test func daylightFactorsAtExtremes() {
    let noon = SolarModel.factors(date: utcDate(2026, 7, 11, 19), latitude: 37.24, longitude: -122.0)
    let midnight = SolarModel.factors(date: utcDate(2026, 7, 11, 7), latitude: 37.24, longitude: -122.0)
    #expect(noon.daylight > 0.95)
    #expect(midnight.daylight < 0.05)
    #expect(noon.twilight < 0.05)
}

@Test func fallbackWithoutCoordinatesStillProducesFactors() {
    let f = SolarModel.factors(date: Date(), latitude: nil, longitude: nil)
    #expect(f.daylight >= 0 && f.daylight <= 1)
    #expect(f.twilight >= 0 && f.twilight <= 1)
}

@Test func goodDayPaletteMatchesAnchor() {
    // mid-Good band (AQI 25), full daylight, no twilight -> exact day anchors
    let a = ScenePalette.anchors(aqi: 25, daylight: 1, twilight: 0)
    #expect(a[0] == RGB(hex: 0x123A8C))
    #expect(a[3] == RGB(hex: 0xA8CDEE))
}

@Test func hazardousNightIsNearBlack() {
    let a = ScenePalette.anchors(aqi: 450, daylight: 0, twilight: 0)
    #expect(a[0].r < 0.1 && a[0].g < 0.1 && a[0].b < 0.1)
}

@Test func paletteIsContinuousAcrossBands() {
    let below = ScenePalette.anchors(aqi: 74.9, daylight: 1, twilight: 0)
    let above = ScenePalette.anchors(aqi: 75.1, daylight: 1, twilight: 0)
    for i in 0..<4 {
        #expect(abs(below[i].r - above[i].r) < 0.02)
        #expect(abs(below[i].g - above[i].g) < 0.02)
        #expect(abs(below[i].b - above[i].b) < 0.02)
    }
}

@Test func meshColorsCountIsNine() {
    #expect(ScenePalette.meshColors(aqi: 25, daylight: 1, twilight: 0).count == 9)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run the test command. Expected: compile FAILURE — `cannot find 'SolarModel' in scope`.

- [ ] **Step 3: Implement `SolarModel`**

```swift
// PurpleAir LAN/Views/Scene/SolarModel.swift
import Foundation

/// Approximate solar position (NOAA simplified equations) driving the
/// scene's day/night blend. Falls back to a local-clock curve when the
/// sensor reports no coordinates.
enum SolarModel {
    static func factors(date: Date, latitude: Double?, longitude: Double?) -> (daylight: Double, twilight: Double) {
        guard let latitude, let longitude else { return clockFactors(date: date) }
        let elev = solarElevationDegrees(date: date, latitude: latitude, longitude: longitude)
        let daylight = smoothstep(-6, 12, elev)
        let twilight = exp(-pow(elev / 6, 2))
        return (daylight, twilight)
    }

    static func solarElevationDegrees(date: Date, latitude: Double, longitude: Double) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hourUTC = Double(cal.component(.hour, from: date))
            + Double(cal.component(.minute, from: date)) / 60

        let gamma = 2 * .pi / 365 * (dayOfYear - 1 + (hourUTC - 12) / 24)
        let declination = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)
        let equationOfTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))

        let solarTimeMinutes = hourUTC * 60 + equationOfTime + 4 * longitude
        let hourAngle = (solarTimeMinutes / 4 - 180) * .pi / 180
        let latR = latitude * .pi / 180
        let sinElevation = sin(latR) * sin(declination) + cos(latR) * cos(declination) * cos(hourAngle)
        return asin(min(max(sinElevation, -1), 1)) * 180 / .pi
    }

    /// No-coordinates fallback: same shape as the solar curve, keyed to the
    /// local clock (dawn ≈ 6, dusk ≈ 19).
    static func clockFactors(date: Date) -> (daylight: Double, twilight: Double) {
        let cal = Calendar.current
        let h = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60
        let daylight = min(max((cos((h - 13) / 12 * .pi) + 0.35) / 1.2, 0), 1)
        let twilight = max(exp(-pow(h - 6.2, 2) / 0.9), exp(-pow(h - 18.8, 2) / 0.9))
        return (daylight, twilight)
    }

    static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
```

- [ ] **Step 4: Implement `ScenePalette`**

```swift
// PurpleAir LAN/Views/Scene/ScenePalette.swift
import SwiftUI

/// Linear-RGB triple used for palette math (SwiftUI Color is opaque).
struct RGB: Equatable {
    let r: Double
    let g: Double
    let b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// The wallpaper's palette: continuous in AQI (anchored at band midpoints),
/// blended day/night by the solar factors, warmed at the horizon in twilight.
enum ScenePalette {
    /// Day anchors [top, upper, lower, horizon] per EPA band.
    private static let day: [[RGB]] = [
        [RGB(hex: 0x123A8C), RGB(hex: 0x2E63C4), RGB(hex: 0x5E93DB), RGB(hex: 0xA8CDEE)], // Good — serene sky
        [RGB(hex: 0x2B4A7E), RGB(hex: 0x5F7BA6), RGB(hex: 0xC99C55), RGB(hex: 0xEECB7F)], // Moderate — golden haze
        [RGB(hex: 0x3A3550), RGB(hex: 0x77573F), RGB(hex: 0xC07A3A), RGB(hex: 0xE8A860)], // USG — amber haze
        [RGB(hex: 0x2E2230), RGB(hex: 0x6E3A2E), RGB(hex: 0xA34A2A), RGB(hex: 0xC86038)], // Unhealthy — smoky brown
        [RGB(hex: 0x1E1428), RGB(hex: 0x4A2244), RGB(hex: 0x7A3060), RGB(hex: 0x94425F)], // V. Unhealthy — maroon dusk
        [RGB(hex: 0x0E0A0E), RGB(hex: 0x2A1016), RGB(hex: 0x4A1220), RGB(hex: 0x641824)], // Hazardous — oxblood
    ]

    /// Night anchors, same shape.
    private static let night: [[RGB]] = [
        [RGB(hex: 0x05070F), RGB(hex: 0x0B1026), RGB(hex: 0x141D3E), RGB(hex: 0x1B2A52)],
        [RGB(hex: 0x070810), RGB(hex: 0x12142A), RGB(hex: 0x242040), RGB(hex: 0x3A3050)],
        [RGB(hex: 0x0A080E), RGB(hex: 0x181022), RGB(hex: 0x2C1A2A), RGB(hex: 0x402438)],
        [RGB(hex: 0x0A0609), RGB(hex: 0x1A0D14), RGB(hex: 0x301420), RGB(hex: 0x421A28)],
        [RGB(hex: 0x080510), RGB(hex: 0x150A1E), RGB(hex: 0x26102E), RGB(hex: 0x331640)],
        [RGB(hex: 0x060406), RGB(hex: 0x12060A), RGB(hex: 0x200A12), RGB(hex: 0x2C0E18)],
    ]

    /// Twilight horizon warmth.
    private static let duskTint = RGB(hex: 0xFF7A3C)

    /// AQI values at which each band's palette applies exactly.
    private static let bandMidpoints: [Double] = [25, 75, 125, 175, 250, 400]

    static func anchors(aqi: Double, daylight: Double, twilight: Double) -> [RGB] {
        // continuous band position from AQI
        let (lower, upper, t) = bandBlend(aqi: aqi)
        return (0..<4).map { i in
            let dayColor = day[lower][i].mixed(with: day[upper][i], amount: t)
            let nightColor = night[lower][i].mixed(with: night[upper][i], amount: t)
            var color = nightColor.mixed(with: dayColor, amount: daylight)
            if i >= 2 { // warm the lower sky / horizon at dawn & dusk
                color = color.mixed(with: duskTint, amount: twilight * (i == 3 ? 0.45 : 0.22))
            }
            return color
        }
    }

    /// Row-major 3×3 colors for MeshGradient: top row, mid row, horizon row.
    static func meshColors(aqi: Double, daylight: Double, twilight: Double) -> [Color] {
        let p = anchors(aqi: aqi, daylight: daylight, twilight: twilight)
        return [
            p[0].color, p[0].mixed(with: p[1], amount: 0.3).color, p[0].color,
            p[1].color, p[1].mixed(with: p[2], amount: 0.5).color, p[1].color,
            p[2].color, p[3].color, p[2].color, // brightest glow bottom-center
        ]
    }

    private static func bandBlend(aqi: Double) -> (lower: Int, upper: Int, t: Double) {
        let clamped = min(max(aqi, bandMidpoints.first!), bandMidpoints.last!)
        for i in 0..<(bandMidpoints.count - 1) where clamped <= bandMidpoints[i + 1] {
            let span = bandMidpoints[i + 1] - bandMidpoints[i]
            return (i, i + 1, (clamped - bandMidpoints[i]) / span)
        }
        return (bandMidpoints.count - 1, bandMidpoints.count - 1, 0)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the test command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add "PurpleAir LAN/Views/Scene/ScenePalette.swift" "PurpleAir LAN/Views/Scene/SolarModel.swift" "PurpleAir LANTests/SceneMathTests.swift"
git commit -m "feat: scene palette (AQI x sun) and solar model"
```

---

### Task 6: `AmbientSceneView` — MeshGradient + particle canvas

Visual component; verified by build + preview (no unit tests — all math it consumes was tested in Task 5).

**Files:**
- Create: `PurpleAir LAN/Views/Scene/AmbientSceneView.swift`

**Interfaces:**
- Consumes: `ScenePalette.meshColors(aqi:daylight:twilight:)`, `SolarModel.factors(date:latitude:longitude:)`, `AQICategory` (Task 2).
- Produces (used by Task 8):

```swift
struct AmbientSceneView: View {
    let aqi: Double        // continuous; drives palette
    let pm25: Double       // corrected µg/m³; drives haze density
    let latitude: Double?
    let longitude: Double?
}
```

- [ ] **Step 1: Implement the view**

```swift
// PurpleAir LAN/Views/Scene/AmbientSceneView.swift
import SwiftUI

/// The full-bleed living wallpaper: a slow-drifting mesh gradient whose
/// palette follows AQI band and sun position, haze motes whose density
/// follows PM2.5, and stars on clean nights.
struct AmbientSceneView: View {
    let aqi: Double
    let pm25: Double
    let latitude: Double?
    let longitude: Double?

    private struct Mote {
        let x: Double, y: Double, radius: Double, speed: Double, phase: Double
    }

    private static let motes: [Mote] = (0..<90).map { i in
        Mote(
            x: Double(i) * 137.508.truncatingRemainder(dividingBy: 100) / 100,
            y: (Double(i) * 61.803).truncatingRemainder(dividingBy: 100) / 100,
            radius: 24 + Double((i * 7919) % 46),
            speed: 0.004 + Double(i % 7) * 0.0012,
            phase: Double(i) * 0.7
        )
    }

    private static let stars: [(x: Double, y: Double, phase: Double, radius: Double)] =
        (0..<70).map { i in
            ((Double(i) * 97.7).truncatingRemainder(dividingBy: 100) / 100,
             (Double(i) * 43.3).truncatingRemainder(dividingBy: 100) / 100 * 0.55,
             Double(i) * 1.31,
             i % 3 == 0 ? 1.5 : 0.9)
        }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sun = SolarModel.factors(date: timeline.date, latitude: latitude, longitude: longitude)

            ZStack {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: meshPoints(t: t),
                    colors: ScenePalette.meshColors(aqi: aqi, daylight: sun.daylight, twilight: sun.twilight)
                )

                Canvas { context, size in
                    drawStars(context: context, size: size, t: t, daylight: sun.daylight)
                    drawHaze(context: context, size: size, t: t)
                }
            }
            .drawingGroup() // Metal-composited; never applied above the material cards
        }
        .ignoresSafeArea()
    }

    /// 3×3 grid: edges pinned, two interior points drift on slow sine paths.
    private func meshPoints(t: TimeInterval) -> [SIMD2<Float>] {
        let cx = Float(0.5 + 0.22 * sin(t / 17))
        let cy = Float(0.42 + 0.08 * cos(t / 23))
        let bx = Float(0.5 + 0.25 * cos(t / 29))
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.45], [cx, cy], [1, 0.5],
            [0, 1], [bx, 1], [1, 1],
        ]
    }

    private func drawStars(context: GraphicsContext, size: CGSize, t: TimeInterval, daylight: Double) {
        guard daylight < 0.18, aqi <= 100 else { return }
        let visibility = 1 - daylight / 0.18
        for star in Self.stars {
            let twinkle = 0.5 + 0.5 * sin(t * 1.3 + star.phase)
            let opacity = (0.25 + 0.55 * twinkle) * visibility
            let r = star.radius * size.width / 400
            let rect = CGRect(
                x: star.x * size.width - r, y: star.y * size.height - r,
                width: r * 2, height: r * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
        }
    }

    private func drawHaze(context: GraphicsContext, size: CGSize, t: TimeInterval) {
        let density = min(max((pm25 - 5) / 150, 0), 1)
        let count = Int(density * Double(Self.motes.count))
        guard count > 0 else { return }
        // haze tone drifts warm as the air worsens
        let warmth = min(aqi / 200, 1)
        let tone = RGB(r: 0.78, g: 0.78, b: 0.8)
            .mixed(with: RGB(hex: 0xC86038), amount: warmth)

        for mote in Self.motes.prefix(count) {
            let x = ((mote.x + t * mote.speed).truncatingRemainder(dividingBy: 1.2) - 0.1) * size.width
            let y = (mote.y + 0.03 * sin(t / 9 + mote.phase)) * size.height
            let r = mote.radius * size.width / 400
            let alpha = (0.05 + 0.07 * density) * (0.6 + 0.4 * sin(t / 5 + mote.phase))
            let gradient = Gradient(stops: [
                .init(color: tone.color.opacity(alpha), location: 0),
                .init(color: .clear, location: 1),
            ])
            context.fill(
                Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                with: .radialGradient(gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r)
            )
        }
    }
}

#Preview("Good day") {
    AmbientSceneView(aqi: 28, pm25: 5, latitude: 37.24, longitude: -122.0)
}

#Preview("Smoke event") {
    AmbientSceneView(aqi: 180, pm25: 100, latitude: 37.24, longitude: -122.0)
}
```

- [ ] **Step 2: Build check**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add "PurpleAir LAN/Views/Scene/AmbientSceneView.swift"
git commit -m "feat: ambient scene view (mesh gradient + haze/stars canvas)"
```

---

### Task 7: Frosted metric cards — `MetricCard`, `AQIScaleBar`, PM/Humidity/Pressure cards

Visual components; verified by build + previews.

**Files:**
- Create: `PurpleAir LAN/Views/Components/MetricCard.swift`
- Create: `PurpleAir LAN/Views/Dashboard/DashboardCards.swift`

**Interfaces:**
- Consumes: `AQIReading`, `AQICategory` (Task 2), `PressureTrend` (Task 4), `AirQuality.comfortDescription` (Task 2).
- Produces (used by Task 8):

```swift
struct MetricCard<Content: View>: View {
    init(icon: String, title: String, footnote: String? = nil, @ViewBuilder content: @escaping () -> Content)
}
struct AQIScaleBar: View { let aqi: Int }
struct PMCard: View { let reading: AQIReading }
struct HumidityCard: View { let humidityPct: Double; let dewPointF: Double }
struct PressureCard: View { let hPa: Double; let trend: PressureTrend? }
```

- [ ] **Step 1: Implement `MetricCard` + `AQIScaleBar`**

```swift
// PurpleAir LAN/Views/Components/MetricCard.swift
import SwiftUI

/// Weather-app style frosted tile: uppercase header, content, footnote.
struct MetricCard<Content: View>: View {
    let icon: String
    let title: String
    var footnote: String?
    @ViewBuilder let content: () -> Content

    init(icon: String, title: String, footnote: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .kerning(0.8)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.bottom, 8)

            content()

            if let footnote {
                Spacer(minLength: 10)
                Text(footnote)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
    }
}

/// The EPA AQI color track with a dot at the current value (UV-index idiom).
struct AQIScaleBar: View {
    let aqi: Int

    private static let stops: [Gradient.Stop] = [
        .init(color: Color(red: 0, green: 228 / 255, blue: 0), location: 0),
        .init(color: Color(red: 0, green: 228 / 255, blue: 0), location: 0.08),
        .init(color: Color(red: 1, green: 1, blue: 0), location: 0.12),
        .init(color: Color(red: 1, green: 1, blue: 0), location: 0.18),
        .init(color: Color(red: 1, green: 126 / 255, blue: 0), location: 0.24),
        .init(color: Color(red: 1, green: 126 / 255, blue: 0), location: 0.28),
        .init(color: Color(red: 1, green: 0, blue: 0), location: 0.34),
        .init(color: Color(red: 1, green: 0, blue: 0), location: 0.38),
        .init(color: Color(red: 143 / 255, green: 63 / 255, blue: 151 / 255), location: 0.50),
        .init(color: Color(red: 143 / 255, green: 63 / 255, blue: 151 / 255), location: 0.58),
        .init(color: Color(red: 126 / 255, green: 0, blue: 35 / 255), location: 0.78),
        .init(color: Color(red: 126 / 255, green: 0, blue: 35 / 255), location: 1),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(stops: Self.stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 1.5).padding(-2.5))
                    .offset(x: geo.size.width * min(Double(aqi) / 500, 1) - 4.5)
                    .animation(.easeInOut(duration: 0.4), value: aqi)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 9)
    }
}
```

- [ ] **Step 2: Implement the three cards**

```swift
// PurpleAir LAN/Views/Dashboard/DashboardCards.swift
import SwiftUI

/// Full-width card: corrected PM2.5, EPA scale bar, health guidance.
struct PMCard: View {
    let reading: AQIReading

    var body: some View {
        MetricCard(
            icon: "aqi.medium",
            title: "PARTICULATE MATTER PM2.5",
            footnote: reading.category.healthGuidance
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reading.correctedPM25, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("µg/m³ · EPA corrected")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                }
                AQIScaleBar(aqi: reading.aqi)
            }
            .foregroundStyle(.white)
        }
    }
}

/// Square card: corrected humidity + comfort word + dew point footnote.
struct HumidityCard: View {
    let humidityPct: Double
    let dewPointF: Double

    var body: some View {
        MetricCard(
            icon: "humidity.fill",
            title: "HUMIDITY",
            footnote: "The dew point is \(Int(dewPointF.rounded()))° right now."
        ) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(humidityPct.rounded()))")
                        .font(.system(size: 30, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Text(AirQuality.comfortDescription(humidity: humidityPct))
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

/// Square card: arc gauge with trend glyph, station pressure, trend footnote.
struct PressureCard: View {
    let hPa: Double
    let trend: PressureTrend?

    private var gaugeFraction: Double {
        switch trend {
        case .falling: 0.32
        case .rising: 0.68
        default: 0.5
        }
    }

    var body: some View {
        MetricCard(
            icon: "gauge.with.needle",
            title: "PRESSURE",
            footnote: trend?.footnote ?? "Gathering pressure history…"
        ) {
            VStack(spacing: 4) {
                PressureGauge(fraction: gaugeFraction, symbolName: trend?.symbolName ?? "minus")
                    .frame(width: 88, height: 56)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(hPa, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 22, weight: .medium))
                        .monospacedDigit()
                    Text("hPa")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
        }
    }
}

/// 270° arc gauge, Weather-style: hairline track, bright progress, end dot.
struct PressureGauge: View {
    let fraction: Double // 0…1 along the arc
    let symbolName: String

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.62)
            let radius = min(geo.size.width, geo.size.height * 1.4) / 2 - 4
            ZStack {
                arc(to: 1, center: center, radius: radius)
                    .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                arc(to: fraction, center: center, radius: radius)
                    .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .position(endPoint(fraction: fraction, center: center, radius: radius))
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .position(center)
            }
        }
    }

    private func angle(for f: Double) -> Angle { .degrees(135 + 270 * f) }

    private func arc(to f: Double, center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            p.addArc(center: center, radius: radius,
                     startAngle: angle(for: 0), endAngle: angle(for: f), clockwise: false)
        }
    }

    private func endPoint(fraction: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let a = angle(for: fraction).radians
        return CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
    }
}

#Preview("Cards on dark") {
    ZStack {
        Color(red: 0.1, green: 0.2, blue: 0.4).ignoresSafeArea()
        VStack(spacing: 8) {
            PMCard(reading: AQIReading(aqi: 28, category: .good, correctedPM25: 5.1, channelsAgree: true))
            HStack(alignment: .top, spacing: 8) {
                HumidityCard(humidityPct: 45, dewPointF: 53)
                PressureCard(hPa: 994.6, trend: .steady)
            }
        }
        .padding(16)
    }
    .environment(\.colorScheme, .dark)
}
```

- [ ] **Step 3: Build check**

Run the Global Constraints build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add "PurpleAir LAN/Views/Components/MetricCard.swift" "PurpleAir LAN/Views/Dashboard/DashboardCards.swift"
git commit -m "feat: frosted metric cards (PM2.5 scale bar, humidity, pressure gauge)"
```

---

### Task 8: Rewrite `DashboardView` — hero, composition, ambient behavior

**Files:**
- Modify: `PurpleAir LAN/Views/DashboardView.swift` (full rewrite of the file)
- Modify: `PurpleAir LAN/Models/PurpleAirData.swift` (delete obsolete display helpers)
- Delete: `PurpleAir LAN/Views/Components/DataTile.swift`

**Interfaces:**
- Consumes: everything produced by Tasks 2–7 (exact signatures listed in those tasks).
- Produces: `DashboardView(hostname:)` — same external signature `ContentView` already uses; no `ContentView` change needed.

- [ ] **Step 1: Rewrite `DashboardView.swift`** (replace the entire file)

```swift
// PurpleAir LAN/Views/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    let hostname: String

    @StateObject private var purpleAirService = PurpleAirService()
    @State private var showingConfiguration = false
    @State private var refreshTimer: Timer?
    @State private var lastUpdateTime: Date?
    @State private var lastData: PurpleAirData?
    @State private var refreshFailed = false
    @State private var chromeVisible = true
    @State private var chromeFadeTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private let pressureStore = PressureHistoryStore()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                AmbientSceneView(
                    aqi: Double(lastData?.airQualityReading?.aqi ?? 25),
                    pm25: lastData?.airQualityReading?.correctedPM25 ?? 0,
                    latitude: lastData?.latitude,
                    longitude: lastData?.longitude
                )
                .overlay(Color.black.opacity(refreshFailed ? 0.1 : 0))

                ScrollView {
                    mainContent
                        .frame(minHeight: geo.size.height)
                }
                .refreshable { await refresh() }

                chrome
            }
        }
        .environment(\.colorScheme, .dark)
        .persistentSystemOverlays(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .contentShape(Rectangle())
        .onTapGesture { showChrome() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Task { await refresh() }
            startAutoRefresh()
            scheduleChromeFade()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            stopAutoRefresh()
            chromeFadeTask?.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
        .sheet(isPresented: $showingConfiguration) {
            NavigationView {
                ConfigurationView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") { showingConfiguration = false }
                        }
                    }
            }
        }
    }

    // MARK: content

    @ViewBuilder private var mainContent: some View {
        if let data = lastData {
            loadedContent(data: data)
        } else if case .error(let message) = purpleAirService.state {
            errorContent(message: message)
        } else {
            loadingContent
        }
    }

    private func loadedContent(data: PurpleAirData) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 64)
            hero(data: data)
            Spacer(minLength: 24)
            cards(data: data)
            footerCaption(data: data)
                .padding(.top, 12)
                .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
    }

    private func hero(data: PurpleAirData) -> some View {
        VStack(spacing: 2) {
            if let place = data.place, !place.isEmpty {
                Text(place.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.7)
                    .foregroundStyle(.white.opacity(0.62))
            }
            if let station = data.geo {
                Text(station)
                    .font(.system(size: 27))
            }
            if let reading = data.airQualityReading {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(reading.aqi)")
                        .font(.system(size: 112, weight: .thin))
                        .contentTransition(.numericText())
                    Text("AQI")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.leading, 30) // optical centering against the unit label
                Text(reading.category.name)
                    .font(.system(size: 21, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let temp = data.displayTemperatureF {
                HStack(spacing: 0) {
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 20, weight: .medium))
                    if let dew = data.displayDewPointF {
                        Text(" · Dew point \(Int(dew.rounded()))°")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
    }

    private func cards(data: PurpleAirData) -> some View {
        VStack(spacing: 8) {
            if let reading = data.airQualityReading {
                PMCard(reading: reading)
            }
            HStack(alignment: .top, spacing: 8) {
                if let humidity = data.displayHumidityPct, let dew = data.displayDewPointF {
                    HumidityCard(humidityPct: humidity, dewPointF: dew)
                }
                if let pressure = data.pressure {
                    PressureCard(hPa: pressure, trend: pressureStore.trend)
                }
            }
        }
    }

    private func footerCaption(data: PurpleAirData) -> some View {
        Group {
            if refreshFailed {
                Text("Reconnecting… last updated \(lastUpdateTime.map { timeFormatter.string(from: $0) } ?? "—")")
                    .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.3).opacity(0.8))
            } else {
                let agreement = data.airQualityReading?.channelsAgree == false
                    ? "sensor channels disagree" : "sensor channels agree"
                Text("Updated \(lastUpdateTime.map { timeFormatter.string(from: $0) } ?? "—") · \(agreement)")
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .font(.system(size: 11.5))
    }

    private var loadingContent: some View {
        VStack(spacing: 30) {
            WeatherSpinner()
            Text("Checking sensor…")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.7))
            Text("Connection Error")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { Task { await refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: chrome

    private var chrome: some View {
        HStack(spacing: 14) {
            Button { Task { await refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(purpleAirService.isLoading)
            Button { showingConfiguration = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .padding(.trailing, 16)
        .opacity(chromeVisible ? 1 : 0)
    }

    private func showChrome() {
        withAnimation(.easeIn(duration: 0.25)) { chromeVisible = true }
        scheduleChromeFade()
    }

    private func scheduleChromeFade() {
        chromeFadeTask?.cancel()
        chromeFadeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 2)) { chromeVisible = false }
        }
    }

    // MARK: data

    private func refresh() async {
        await purpleAirService.fetchSensorData(from: hostname)
        switch purpleAirService.state {
        case .loaded(let data):
            withAnimation(.easeInOut(duration: 1)) {
                lastData = data
                refreshFailed = false
            }
            lastUpdateTime = Date()
            if let pressure = data.pressure {
                pressureStore.record(pressure)
            }
        case .error:
            // keep showing cached data; surface the failure in the footer
            if lastData != nil { refreshFailed = true }
        default:
            break
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                if !purpleAirService.isLoading {
                    await refresh()
                }
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    DashboardView(hostname: "purpleair.lan")
}
```

Note: `PurpleAirData` must conform to `Equatable` for the `withAnimation` block? It does not need to — `lastData` assignment inside `withAnimation` animates dependent views regardless. Do NOT add an Equatable conformance.

- [ ] **Step 2: Delete the superseded tile component and obsolete model helpers**

```bash
rm "PurpleAir LAN/Views/Components/DataTile.swift"
```

In `PurpleAir LAN/Models/PurpleAirData.swift`, delete the now-unused display helpers: the entire `// MARK: - Computed Properties for Display` extension (`temperatureDisplay`, `humidityDisplay`, `pressureDisplay`, `aqiDisplay`, `aqiBackgroundColor`, `parseRGBColor`) **and** the `// MARK: - AQI Quality Description` extension (`aqiQualityDescription`). Keep the stored properties (including `pm25AqiB`/`p25AqicB` — harmless decode-only fields) and the Task 3 `Corrected display values` extension.

Check for stray references before building: `grep -rn "temperatureDisplay\|aqiDisplay\|aqiBackgroundColor\|aqiQualityDescription\|DataTile" "PurpleAir LAN"` — expect no matches outside this diff (ConfigurationView uses only `data.geo`/`data.place`).

- [ ] **Step 3: Build + full test suite**

Run the build command, then the test command. Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A "PurpleAir LAN"
git commit -m "feat: living-wallpaper dashboard (hero, frosted cards, ambient chrome)"
```

---

### Task 9: End-to-end verification on the simulator

**Files:** none created (screenshots go to the session scratchpad).

**Interfaces:** consumes the finished app; produces screenshots + a PASS/FAIL report.

- [ ] **Step 1: Build and install** (recipe in `.claude/skills/verify/SKILL.md`)

```bash
xcodebuild -project "PurpleAir LAN.xcodeproj" -scheme "PurpleAir LAN" -sdk iphonesimulator -configuration Debug -derivedDataPath <scratchpad>/dd build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; open -a Simulator
xcrun simctl install booted "<scratchpad>/dd/Build/Products/Debug-iphonesimulator/PurpleAir LAN.app"
```

- [ ] **Step 2: Live-sensor run**

Seed `purpleair.lan` if needed (recipe in the verify skill), launch, wait ~6 s, screenshot. Check: mesh scene visible (band palette per the current live AQI and clock), hero AQI numeral + category + temp·dew line, three frosted cards, footer caption. Note: displayed temperature should read ~8 °F *lower* than the raw sensor value — that is correct behavior.

- [ ] **Step 3: Chrome-fade check**

Screenshot immediately after launch (chrome visible) and again after ~8 s (chrome gone).

- [ ] **Step 4: Error-state check**

Seed hostname `nonexistent.invalid`, relaunch, screenshot: error view over dim scene with Try Again. Restore `purpleair.lan` afterwards.

- [ ] **Step 5: Report** with screenshots inline; fix-forward any visual defects found (spacing, contrast, clipping) as small follow-up commits.

---

## Self-review notes

- Spec coverage: pipeline (Task 2–3), pressure trend (4), scene (5–6), cards/hero/ambient (7–8), states (8), verification (9). Spec's "switch to /json" — Task 3. Spec's "delete DataTile" — Task 8. ✔
- Type consistency: `AQIReading` fields, `PressureTrend` cases, `ScenePalette.meshColors` signature, and card initializers are used identically across Tasks 6–8. ✔
- Known simplification vs spec: scene band crossfade emerges from the continuous AQI palette interpolation (Task 5) rather than an explicit 2 s `withAnimation`; data-arrival changes still animate via the `withAnimation` in `refresh()`. ✔
