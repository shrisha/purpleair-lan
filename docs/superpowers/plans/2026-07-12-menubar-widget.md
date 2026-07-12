# PurpleAir Bar + PurpleAirKit Monorepo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract shared Swift into a local `PurpleAirKit` SwiftPM package consumed by the iOS app, and build "PurpleAir Bar" — an ultra-low-power macOS menu bar widget per `docs/superpowers/specs/2026-07-12-menubar-widget-design.md`.

**Architecture:** Package first (copy sources in, publicize, move unit tests — package green standalone), then rewire iOS to consume it (deleting its copies), then a hand-authored macOS app project with a pure `ReachabilityPolicy` state machine driving an `NSBackgroundActivityScheduler`-based `SensorMonitor`, a colored-dot `MenuBarExtra` label, and a 340pt living-wallpaper panel reusing `AmbientSceneView`.

**Tech Stack:** SwiftPM (tools 6.0, Swift 5 language mode), SwiftUI `MenuBarExtra`, Network framework (`NWPathMonitor`), `NSBackgroundActivityScheduler`, `SMAppService`, Swift Testing.

## Global Constraints

- Work happens on branch `menubar-widget` (created by the executor before Task 1).
- Package platforms: `.iOS(.v18), .macOS(.v15)`. macOS app deployment target `15.0`, bundle id `com.sr.PurpleAir-Bar`, product name `PurpleAir Bar`, `LSUIElement = true`, App Sandbox + `com.apple.security.network.client`, ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`).
- Kit test command (from repo root): `cd PurpleAirKit && swift test 2>&1 | tail -5` → expect `Test run with N tests … passed`.
- iOS build command: `xcodebuild -project "PurpleAir LAN.xcodeproj" -scheme "PurpleAir LAN" -sdk iphonesimulator -configuration Debug build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`.
- iOS smoke-test command: `xcodebuild test -project "PurpleAir LAN.xcodeproj" -scheme "PurpleAir LAN" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'PurpleAir LANTests' 2>&1 | tail -5` → `** TEST SUCCEEDED **`.
- Mac build command: `xcodebuild -project PurpleAirBar.xcodeproj -scheme "PurpleAir Bar" -configuration Debug -derivedDataPath /private/tmp/claude-501/-Users-shrisha-dev-purpleair-lan/4a6d99ca-454a-49a2-a36c-2c301ad39789/scratchpad/ddmac build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`. (If the auto-scheme is not found, add `-list` to inspect; the single app target generates a scheme named `PurpleAir Bar`.)
- iOS app behavior must not change; the live sensor is `purpleair.lan` on this Mac's LAN.
- Every commit message ends with a blank line then `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Create the PurpleAirKit package (sources copied in + publicized, tests moved)

The package must build and test green standalone. The iOS app is NOT touched in this task (it keeps compiling its own copies; they're deleted in Task 2), so the repo stays green at every commit.

**Files:**
- Create: `PurpleAirKit/Package.swift`
- Create: `PurpleAirKit/Sources/PurpleAirKit/` — copies of `PurpleAir LAN/Models/AirQuality.swift`, `PurpleAir LAN/Models/PurpleAirData.swift`, `PurpleAir LAN/Services/PurpleAirService.swift`, `PurpleAir LAN/Services/PressureHistoryStore.swift`, `PurpleAir LAN/Views/Scene/ScenePalette.swift`, `PurpleAir LAN/Views/Scene/SolarModel.swift`, `PurpleAir LAN/Views/Scene/AmbientSceneView.swift`, plus new `AQIScaleBar.swift` (the `AQIScaleBar` struct copied out of `PurpleAir LAN/Views/Components/MetricCard.swift` — copy only; do not edit the iOS file yet)
- Move (git mv): `PurpleAir LANTests/AirQualityTests.swift`, `PurpleAir LANTests/PurpleAirDataTests.swift`, `PurpleAir LANTests/PressureHistoryStoreTests.swift`, `PurpleAir LANTests/SceneMathTests.swift` → `PurpleAirKit/Tests/PurpleAirKitTests/`

**Interfaces:**
- Consumes: the existing app sources (read-only copies).
- Produces the public API Tasks 2–6 rely on:

```swift
public enum AQICategory: Int, CaseIterable { case good, moderate, unhealthySensitive, unhealthy, veryUnhealthy, hazardous
    public var name: String; public var epaColor: Color; public var healthGuidance: String }
public struct AQIReading: Equatable {
    public let aqi: Int; public let category: AQICategory; public let correctedPM25: Double; public let channelsAgree: Bool
    public init(aqi: Int, category: AQICategory, correctedPM25: Double, channelsAgree: Bool) }
public enum AirQuality { /* all static funcs public */ }
public struct PurpleAirData: Codable { /* all stored + computed properties public */ }
public enum APIState { case idle, loading, loaded(PurpleAirData), error(String) }
@MainActor public final class PurpleAirService: ObservableObject {
    @Published public var state: APIState
    public init(urlSession: URLSession = .shared)
    public func fetchSensorData(from hostname: String) async
    public var hasData: Bool; public var currentData: PurpleAirData?; public var isLoading: Bool; public var errorMessage: String? }
public enum PressureTrend: Equatable { case rising(rapid: Bool), falling(rapid: Bool), steady
    public var symbolName: String; public var footnote: String }
public final class PressureHistoryStore {
    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init)
    public func record(_ hPa: Double); public var trend: PressureTrend? }
public struct RGB: Equatable { public let r, g, b: Double; public init(r:g:b:); public init(hex: UInt32)
    public func mixed(with other: RGB, amount: Double) -> RGB; public var color: Color }
public enum ScenePalette { public static func anchors(aqi:daylight:twilight:) -> [RGB]
    public static func meshColors(aqi:daylight:twilight:) -> [Color] }
public enum SolarModel { public static func factors(date: Date, latitude: Double?, longitude: Double?) -> (daylight: Double, twilight: Double)
    public static func solarElevationDegrees(date: Date, latitude: Double, longitude: Double) -> Double }
public struct AmbientSceneView: View { public init(aqi: Double, pm25: Double, latitude: Double?, longitude: Double?); public var body: some View }
public struct AQIScaleBar: View { public init(aqi: Int); public var body: some View }
```

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurpleAirKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PurpleAirKit", targets: ["PurpleAirKit"]),
    ],
    targets: [
        .target(
            name: "PurpleAirKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PurpleAirKitTests",
            dependencies: ["PurpleAirKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

(`swiftLanguageMode(.v5)` keeps the moved code compiling exactly as it did in the app targets; migrating to Swift 6 strict concurrency is not this project's job.)

- [ ] **Step 2: Copy the seven source files and extract AQIScaleBar**

```bash
mkdir -p PurpleAirKit/Sources/PurpleAirKit PurpleAirKit/Tests/PurpleAirKitTests
cp "PurpleAir LAN/Models/AirQuality.swift" "PurpleAir LAN/Models/PurpleAirData.swift" \
   "PurpleAir LAN/Services/PurpleAirService.swift" "PurpleAir LAN/Services/PressureHistoryStore.swift" \
   "PurpleAir LAN/Views/Scene/ScenePalette.swift" "PurpleAir LAN/Views/Scene/SolarModel.swift" \
   "PurpleAir LAN/Views/Scene/AmbientSceneView.swift" PurpleAirKit/Sources/PurpleAirKit/
```

Then create `PurpleAirKit/Sources/PurpleAirKit/AQIScaleBar.swift` containing exactly the `AQIScaleBar` struct (with its `stops` array and `body`) copied from `PurpleAir LAN/Views/Components/MetricCard.swift`, plus `import SwiftUI` at the top. Do not modify the iOS file.

- [ ] **Step 3: Move the four test files and retarget their import**

```bash
git mv "PurpleAir LANTests/AirQualityTests.swift" PurpleAirKit/Tests/PurpleAirKitTests/
git mv "PurpleAir LANTests/PurpleAirDataTests.swift" PurpleAirKit/Tests/PurpleAirKitTests/
git mv "PurpleAir LANTests/PressureHistoryStoreTests.swift" PurpleAirKit/Tests/PurpleAirKitTests/
git mv "PurpleAir LANTests/SceneMathTests.swift" PurpleAirKit/Tests/PurpleAirKitTests/
```

In each moved file change `@testable import PurpleAir_LAN` → `@testable import PurpleAirKit`.

- [ ] **Step 4: Publicize the package sources**

In `PurpleAirKit/Sources/PurpleAirKit/` only (never the iOS copies), add `public` so the Interfaces block above holds. Mechanical rules:
- Every type in the Interfaces block: `public struct` / `public enum` / `public final class` (`PurpleAirService` keeps `@MainActor`).
- Every property, computed property, initializer, and method listed: `public`. `PurpleAirData`'s stored properties and the computed `airQualityReading` / `displayTemperatureF` / `displayHumidityPct` / `displayDewPointF` all become `public let` / `public var`. `CodingKeys` stays internal (Codable synthesis works cross-module through the protocol witness).
- Add the explicit `public init(aqi:category:correctedPM25:channelsAgree:)` to `AQIReading` (memberwise init is internal by default; the iOS previews construct readings).
- `AmbientSceneView` and `AQIScaleBar`: `public struct`, explicit `public init` storing the lets, `public var body`. For `AmbientSceneView` add:

```swift
    public init(aqi: Double, pm25: Double, latitude: Double?, longitude: Double?) {
        self.aqi = aqi
        self.pm25 = pm25
        self.latitude = latitude
        self.longitude = longitude
    }
```

and for `AQIScaleBar`:

```swift
    public init(aqi: Int) { self.aqi = aqi }
```

- `RGB`: `public struct`, `public let r/g/b`, both inits, `mixed`, `color` public. `ScenePalette.anchors`/`meshColors`, `SolarModel.factors`/`solarElevationDegrees` public; `SolarModel.clockFactors`/`smoothstep` and `ScenePalette`'s private tables stay as they are (tests use `@testable`).
- `APIState`, `PressureTrend` (cases are public automatically once the enum is), `PressureHistoryStore.init/record/trend` public.

- [ ] **Step 5: Run the package tests**

Run: `cd PurpleAirKit && swift test 2>&1 | tail -5`
Expected: all moved tests pass (≈41 tests). Common failures and their meaning: "cannot find X in scope" → a missed `public` or a file not copied; "initializer is inaccessible" → missing public init.

- [ ] **Step 6: Confirm the iOS app is untouched and still green**

Run the iOS build command (Global Constraints). Expected: `** BUILD SUCCEEDED **` (the app still compiles its own copies; the deleted iOS test files are the only change to its tree, and they weren't part of the app target).

- [ ] **Step 7: Commit**

```bash
git add PurpleAirKit "PurpleAir LANTests"
git commit -m "feat: extract PurpleAirKit package with shared core + tests"
```

---

### Task 2: Point the iOS app at PurpleAirKit (delete its copies)

**Files:**
- Modify: `PurpleAir LAN.xcodeproj/project.pbxproj` (package reference wiring)
- Delete: `PurpleAir LAN/Models/AirQuality.swift`, `PurpleAir LAN/Models/PurpleAirData.swift`, `PurpleAir LAN/Services/PurpleAirService.swift`, `PurpleAir LAN/Services/PressureHistoryStore.swift`, `PurpleAir LAN/Views/Scene/ScenePalette.swift`, `PurpleAir LAN/Views/Scene/SolarModel.swift`, `PurpleAir LAN/Views/Scene/AmbientSceneView.swift`
- Modify: `PurpleAir LAN/Views/Components/MetricCard.swift` (remove the `AQIScaleBar` struct; add nothing else)
- Modify: `PurpleAir LAN/Views/DashboardView.swift`, `PurpleAir LAN/Views/ConfigurationView.swift`, `PurpleAir LAN/Views/Dashboard/DashboardCards.swift` (add `import PurpleAirKit`)

**Interfaces:**
- Consumes: the Task 1 public API, exactly as listed there.
- Produces: an iOS app identical in behavior, now importing `PurpleAirKit`.

- [ ] **Step 1: Add the local package to the iOS pbxproj**

Three edits to `PurpleAir LAN.xcodeproj/project.pbxproj` (IDs are new 24-hex-char identifiers; use them exactly):

1. Immediately after the `/* End PBXBuildFile section */`-less top of the objects list — the file currently has no `PBXBuildFile` section, so create one right after the `objects = {` opening line's first section boundary (place it before the `PBXFileReference` section):

```
/* Begin PBXBuildFile section */
		AA0000000000000000000112 /* PurpleAirKit in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000000111 /* PurpleAirKit */; };
/* End PBXBuildFile section */
```

2. In the app target's `PBXFrameworksBuildPhase` (ID `9D8B08942E405EBB00541770`), change `files = (` `);` to:

```
			files = (
				AA0000000000000000000112 /* PurpleAirKit in Frameworks */,
			);
```

(The other two Frameworks phases — test targets — stay empty.)

3. In the app `PBXNativeTarget` (ID `9D8B08962E405EBB00541770`), change the empty `packageProductDependencies = (` `);` to:

```
			packageProductDependencies = (
				AA0000000000000000000111 /* PurpleAirKit */,
			);
```

4. In the `PBXProject` block (search for `isa = PBXProject;`), add directly after the `mainGroup = … ;` line:

```
			packageReferences = (
				AA0000000000000000000110 /* XCLocalSwiftPackageReference "PurpleAirKit" */,
			);
```

5. Before the final `};` + `rootObject` lines, add two new sections (alphabetical placement near the end matches Xcode convention but is not required):

```
/* Begin XCLocalSwiftPackageReference section */
		AA0000000000000000000110 /* XCLocalSwiftPackageReference "PurpleAirKit" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = PurpleAirKit;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		AA0000000000000000000111 /* PurpleAirKit */ = {
			isa = XCSwiftPackageProductDependency;
			productName = PurpleAirKit;
		};
/* End XCSwiftPackageProductDependency section */
```

- [ ] **Step 2: Delete the duplicated sources and trim MetricCard**

```bash
git rm "PurpleAir LAN/Models/AirQuality.swift" "PurpleAir LAN/Models/PurpleAirData.swift" \
       "PurpleAir LAN/Services/PurpleAirService.swift" "PurpleAir LAN/Services/PressureHistoryStore.swift" \
       "PurpleAir LAN/Views/Scene/ScenePalette.swift" "PurpleAir LAN/Views/Scene/SolarModel.swift" \
       "PurpleAir LAN/Views/Scene/AmbientSceneView.swift"
rmdir "PurpleAir LAN/Views/Scene" 2>/dev/null || true
```

In `PurpleAir LAN/Views/Components/MetricCard.swift`: delete the entire `AQIScaleBar` struct (it now lives in the kit). `MetricCard` itself references no kit types, so this file needs no import.

- [ ] **Step 3: Add imports**

Add `import PurpleAirKit` below `import SwiftUI` in:
- `PurpleAir LAN/Views/DashboardView.swift`
- `PurpleAir LAN/Views/ConfigurationView.swift`
- `PurpleAir LAN/Views/Dashboard/DashboardCards.swift`

(`ContentView.swift`, `PurpleAirLANApp.swift`, `WeatherSpinner.swift` reference no kit types — leave them.)

- [ ] **Step 4: Build + smoke test**

Run the iOS build command → `** BUILD SUCCEEDED **`; then the iOS smoke-test command → `** TEST SUCCEEDED **`. If the build fails with "no such module 'PurpleAirKit'", the pbxproj edit in Step 1 is malformed — re-check IDs match across all five insertions.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: iOS app consumes PurpleAirKit; drop duplicated sources"
```

---

### Task 3: macOS app skeleton (project, plists, workspace, placeholder menu bar item)

**Files:**
- Create: `PurpleAirBar.xcodeproj/project.pbxproj`
- Create: `PurpleAirBar/PurpleAirBarApp.swift` (placeholder)
- Create: `PurpleAirBar/PurpleAirBar-Info.plist`
- Create: `PurpleAirBar/PurpleAirBar.entitlements`
- Create: `PurpleAir.xcworkspace/contents.xcworkspacedata`

**Interfaces:**
- Consumes: the PurpleAirKit package (product dependency only; placeholder imports it to prove linkage).
- Produces: a building, launchable `PurpleAir Bar.app` with a static menu bar item; Tasks 5–6 replace the placeholder views.

- [ ] **Step 1: Write the project file**

`PurpleAirBar.xcodeproj/project.pbxproj`, verbatim:

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		BB0000000000000000000012 /* PurpleAirKit in Frameworks */ = {isa = PBXBuildFile; productRef = BB0000000000000000000011 /* PurpleAirKit */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		BB0000000000000000000005 /* PurpleAir Bar.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "PurpleAir Bar.app"; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		BB0000000000000000000003 /* PurpleAirBar */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = PurpleAirBar;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		BB0000000000000000000008 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				BB0000000000000000000012 /* PurpleAirKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		BB0000000000000000000002 = {
			isa = PBXGroup;
			children = (
				BB0000000000000000000003 /* PurpleAirBar */,
				BB0000000000000000000004 /* Products */,
			);
			sourceTree = "<group>";
		};
		BB0000000000000000000004 /* Products */ = {
			isa = PBXGroup;
			children = (
				BB0000000000000000000005 /* PurpleAir Bar.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		BB0000000000000000000006 /* PurpleAir Bar */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BB0000000000000000000023 /* Build configuration list for PBXNativeTarget "PurpleAir Bar" */;
			buildPhases = (
				BB0000000000000000000007 /* Sources */,
				BB0000000000000000000008 /* Frameworks */,
				BB0000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				BB0000000000000000000003 /* PurpleAirBar */,
			);
			name = "PurpleAir Bar";
			packageProductDependencies = (
				BB0000000000000000000011 /* PurpleAirKit */,
			);
			productName = "PurpleAir Bar";
			productReference = BB0000000000000000000005 /* PurpleAir Bar.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		BB0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
			};
			buildConfigurationList = BB0000000000000000000020 /* Build configuration list for PBXProject "PurpleAirBar" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = BB0000000000000000000002;
			packageReferences = (
				BB0000000000000000000010 /* XCLocalSwiftPackageReference "PurpleAirKit" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = BB0000000000000000000004 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				BB0000000000000000000006 /* PurpleAir Bar */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		BB0000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		BB0000000000000000000007 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		BB0000000000000000000021 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		BB0000000000000000000022 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		BB0000000000000000000024 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = "PurpleAirBar/PurpleAirBar.entitlements";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_HARDENED_RUNTIME = NO;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "PurpleAirBar/PurpleAirBar-Info.plist";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "com.sr.PurpleAir-Bar";
				PRODUCT_NAME = "$(TARGET_NAME)";
			};
			name = Debug;
		};
		BB0000000000000000000025 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = "PurpleAirBar/PurpleAirBar.entitlements";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_HARDENED_RUNTIME = NO;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "PurpleAirBar/PurpleAirBar-Info.plist";
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = "com.sr.PurpleAir-Bar";
				PRODUCT_NAME = "$(TARGET_NAME)";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		BB0000000000000000000020 /* Build configuration list for PBXProject "PurpleAirBar" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				BB0000000000000000000021 /* Debug */,
				BB0000000000000000000022 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		BB0000000000000000000023 /* Build configuration list for PBXNativeTarget "PurpleAir Bar" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				BB0000000000000000000024 /* Debug */,
				BB0000000000000000000025 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		BB0000000000000000000010 /* XCLocalSwiftPackageReference "PurpleAirKit" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = PurpleAirKit;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		BB0000000000000000000011 /* PurpleAirKit */ = {
			isa = XCSwiftPackageProductDependency;
			productName = PurpleAirKit;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = BB0000000000000000000001 /* Project object */;
}
```

- [ ] **Step 2: Info.plist and entitlements**

`PurpleAirBar/PurpleAirBar-Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Menu bar only: no Dock icon, no app menu. -->
	<key>LSUIElement</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<!-- LAN sensors serve plain HTTP on a user-configurable host; a
		     per-domain exception is impossible. Same rationale as the iOS app. -->
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
</dict>
</plist>
```

`PurpleAirBar/PurpleAirBar.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Placeholder app**

`PurpleAirBar/PurpleAirBarApp.swift`:

```swift
import SwiftUI
import PurpleAirKit

@main
struct PurpleAirBarApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("PurpleAir Bar — placeholder")
                .padding()
        } label: {
            Image(systemName: "aqi.medium")
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Workspace**

`PurpleAir.xcworkspace/contents.xcworkspacedata`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:PurpleAir LAN.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:PurpleAirBar.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:PurpleAirKit">
   </FileRef>
</Workspace>
```

- [ ] **Step 5: Build and launch**

Run the Mac build command (Global Constraints) → `** BUILD SUCCEEDED **`. Then:

```bash
open "/private/tmp/claude-501/-Users-shrisha-dev-purpleair-lan/4a6d99ca-454a-49a2-a36c-2c301ad39789/scratchpad/ddmac/Build/Products/Debug/PurpleAir Bar.app"
sleep 3 && pgrep -fl "PurpleAir Bar" && echo RUNNING
```

Expected: process running (a small aqi glyph appears in the menu bar). Then quit it: `pkill -f "PurpleAir Bar" || true`.

- [ ] **Step 6: Commit**

```bash
git add PurpleAirBar.xcodeproj PurpleAirBar PurpleAir.xcworkspace
git commit -m "feat: PurpleAir Bar macOS app skeleton + workspace"
```

---

### Task 4: `ReachabilityPolicy` (pure state machine in the kit, TDD)

**Files:**
- Create: `PurpleAirKit/Sources/PurpleAirKit/ReachabilityPolicy.swift`
- Test: `PurpleAirKit/Tests/PurpleAirKitTests/ReachabilityPolicyTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (used by Task 5):

```swift
public struct ReachabilityPolicy {
    public enum Phase: Equatable { case home, searching, suspended }
    public enum Event: Equatable { case probeSucceeded, probeFailed, pathSatisfied, pathUnsatisfied, pathChanged, slept, woke, kicked }
    public enum Action: Equatable { case probe(after: TimeInterval), idle }
    public private(set) var phase: Phase          // starts .searching
    public private(set) var consecutiveFailures: Int
    public init()
    public mutating func handle(_ event: Event) -> Action
}
```

- [ ] **Step 1: Write the failing tests**

```swift
// PurpleAirKit/Tests/PurpleAirKitTests/ReachabilityPolicyTests.swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd PurpleAirKit && swift test 2>&1 | tail -5`
Expected: compile FAILURE — `cannot find 'ReachabilityPolicy' in scope`.

- [ ] **Step 3: Implement**

```swift
// PurpleAirKit/Sources/PurpleAirKit/ReachabilityPolicy.swift
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
```

- [ ] **Step 4: Run to verify pass**

Run: `cd PurpleAirKit && swift test 2>&1 | tail -5` → all tests pass (previous ≈41 + 11 new).

- [ ] **Step 5: Commit**

```bash
git add PurpleAirKit
git commit -m "feat: ReachabilityPolicy state machine for the menu bar monitor"
```

---

### Task 5: `SensorMonitor` + menu bar label

**Files:**
- Create: `PurpleAirBar/SensorMonitor.swift`
- Create: `PurpleAirBar/MenuBarLabel.swift`
- Modify: `PurpleAirBar/PurpleAirBarApp.swift` (wire monitor + label)

**Interfaces:**
- Consumes: `ReachabilityPolicy` (Task 4), `PurpleAirData`/`AQIReading`/`AQICategory`/`PressureHistoryStore` (Task 1).
- Produces (used by Task 6):

```swift
@MainActor final class SensorMonitor: ObservableObject {
    static let shared: SensorMonitor
    @Published private(set) var phase: ReachabilityPolicy.Phase
    @Published private(set) var lastData: PurpleAirData?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isStale: Bool      // home, but the last probe(s) failed
    @AppStorage("sensorHostname") var hostname: String   // default "purpleair.lan"
    let pressureStore: PressureHistoryStore
    func start()
    func hostnameDidChange()
    func panelOpened()
}
```

- [ ] **Step 1: Implement SensorMonitor**

```swift
// PurpleAirBar/SensorMonitor.swift
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
```

- [ ] **Step 2: Implement the label**

```swift
// PurpleAirBar/MenuBarLabel.swift
import SwiftUI
import AppKit
import PurpleAirKit

/// The always-visible part. Reachable: pre-tinted EPA-colored dot + AQI number
/// (SwiftUI menu bar labels force template rendering, so color must arrive as a
/// non-template NSImage). Unreachable: dim template ghost so Quit stays reachable.
struct MenuBarLabel: View {
    @ObservedObject private var monitor = SensorMonitor.shared

    var body: some View {
        if monitor.phase == .home, let reading = monitor.lastData?.airQualityReading {
            HStack(spacing: 4) {
                Image(nsImage: StatusDot.image(for: reading.category))
                Text("\(reading.aqi)")
                    .monospacedDigit()
            }
        } else {
            Image(nsImage: StatusDot.ghost)
        }
    }
}

enum StatusDot {
    private static var cache: [AQICategory: NSImage] = [:]

    /// 9 pt circle filled with the EPA category color, hairline dark ring for
    /// contrast on Tahoe's transparent menu bar. Non-template on purpose.
    static func image(for category: AQICategory) -> NSImage {
        if let cached = cache[category] { return cached }
        let image = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { rect in
            let inset = rect.insetBy(dx: 0.5, dy: 0.5)
            NSColor(category.epaColor).setFill()
            NSBezierPath(ovalIn: inset).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let ring = NSBezierPath(ovalIn: inset)
            ring.lineWidth = 0.5
            ring.stroke()
            return true
        }
        image.isTemplate = false
        cache[category] = image
        return image
    }

    /// Dim template glyph: template + alpha keeps the system's automatic
    /// black/white flipping while reading as "asleep".
    static let ghost: NSImage = {
        let symbol = NSImage(systemSymbolName: "aqi.medium", accessibilityDescription: "PurpleAir sensor unreachable")!
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))!
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
```

- [ ] **Step 3: Wire into the app**

Replace `PurpleAirBar/PurpleAirBarApp.swift` with:

```swift
import SwiftUI
import PurpleAirKit

@main
struct PurpleAirBarApp: App {
    init() {
        SensorMonitor.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Panel arrives in the next task")
                .padding()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 4: Build, launch against the live sensor**

Run the Mac build command → `** BUILD SUCCEEDED **`. Launch the built app (`open …/PurpleAir Bar.app`), wait 8 s, then `curl -s -m 4 "http://purpleair.lan/json" >/dev/null && echo SENSOR_UP`. Both the sensor and the app being up means the label should now show the colored dot + AQI (the executor verifies visually in Task 7; here process-running + build green is the gate). Quit: `pkill -f "PurpleAir Bar"`.

- [ ] **Step 5: Commit**

```bash
git add PurpleAirBar
git commit -m "feat: sensor monitor (policy-driven, coalesced polling) + menu bar label"
```

---

### Task 6: The panel (home + away) with footer controls

**Files:**
- Create: `PurpleAirBar/PanelView.swift`
- Modify: `PurpleAirBar/PurpleAirBarApp.swift` (use PanelView)

**Interfaces:**
- Consumes: `SensorMonitor` (Task 5), `AmbientSceneView`/`AQIScaleBar`/`AirQuality`/`PressureTrend` (kit).
- Produces: the finished UI.

- [ ] **Step 1: Implement PanelView**

```swift
// PurpleAirBar/PanelView.swift
import SwiftUI
import ServiceManagement
import AppKit
import PurpleAirKit

/// 340 pt living-wallpaper panel. Exists only while open — the scene's
/// TimelineView animates for free and tears down on close.
struct PanelView: View {
    @ObservedObject private var monitor = SensorMonitor.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var editingHostname = false
    @State private var hostnameDraft = ""

    var body: some View {
        ZStack {
            AmbientSceneView(
                aqi: monitor.phase == .home ? Double(monitor.lastData?.airQualityReading?.aqi ?? 25) : 25,
                pm25: monitor.phase == .home ? (monitor.lastData?.airQualityReading?.correctedPM25 ?? 0) : 0,
                latitude: monitor.lastData?.latitude,
                longitude: monitor.lastData?.longitude
            )
            .overlay(Color.black.opacity(monitor.phase == .home ? 0 : 0.2))

            VStack(spacing: 0) {
                if monitor.phase == .home, let data = monitor.lastData {
                    homeContent(data: data)
                } else {
                    awayContent
                }
                footer
            }
        }
        .frame(width: 340, height: 440)
        .environment(\.colorScheme, .dark)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            monitor.panelOpened()
        }
    }

    // MARK: home

    private func homeContent(data: PurpleAirData) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 20)

            Text(stationCaption(data: data))
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.62))

            if let reading = data.airQualityReading {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(reading.aqi)")
                        .font(.system(size: 64, weight: .thin))
                        .contentTransition(.numericText())
                    Text("AQI")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.leading, 18) // optical centering against the unit
                Text(reading.category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let temp = data.displayTemperatureF {
                HStack(spacing: 0) {
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 13, weight: .medium))
                    if let dew = data.displayDewPointF {
                        Text(" · Dew point \(Int(dew.rounded()))°")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 14)

            if let reading = data.airQualityReading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(reading.correctedPM25, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 20, weight: .medium))
                            .monospacedDigit()
                        Text("µg/m³ · EPA corrected")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    AQIScaleBar(aqi: reading.aqi)
                    Text(reading.category.healthGuidance)
                        .font(.system(size: 11))
                        .lineSpacing(2)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            HStack(alignment: .top) {
                if let humidity = data.displayHumidityPct {
                    statColumn(
                        label: "HUMIDITY",
                        value: "\(Int(humidity.rounded())) %",
                        detail: AirQuality.comfortDescription(humidity: humidity)
                    )
                }
                Spacer()
                if let pressure = data.pressure {
                    statColumn(
                        label: "PRESSURE",
                        value: String(format: "%.1f hPa", pressure),
                        detail: nil,
                        trailingSymbol: monitor.pressureStore.trend?.symbolName ?? "minus"
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 10)
        }
        .foregroundStyle(.white)
    }

    private func stationCaption(data: PurpleAirData) -> String {
        [data.place?.uppercased(), data.geo?.uppercased()]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func statColumn(label: String, value: String, detail: String?, trailingSymbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.white.opacity(0.62))
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: away

    private var awayContent: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "aqi.medium")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.5))
            Text("Looking for your PurpleAir")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("It appears automatically when this Mac can reach \(monitor.hostname).")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let last = monitor.lastUpdate, let aqi = monitor.lastData?.airQualityReading?.aqi {
                Text("Last seen \(last.formatted(date: .omitted, time: .shortened)) · AQI \(aqi)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5)
            HStack(spacing: 10) {
                if editingHostname {
                    TextField("hostname or IP", text: $hostnameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit(saveHostname)
                    Button("Save", action: saveHostname)
                        .font(.system(size: 11))
                    Button("Cancel") { editingHostname = false }
                        .font(.system(size: 11))
                } else {
                    Text(footerCaption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(footerColor)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        if let url = URL(string: "http://\(monitor.hostname)/") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                    .help("Open the sensor's page")

                    Menu {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                        Button("Change Sensor Address…") {
                            hostnameDraft = monitor.hostname
                            editingHostname = true
                        }
                        Divider()
                        Button("Quit PurpleAir Bar") { NSApp.terminate(nil) }
                            .keyboardShortcut("q")
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var footerCaption: String {
        let time = monitor.lastUpdate?.formatted(date: .omitted, time: .shortened) ?? "—"
        switch (monitor.phase, monitor.isStale) {
        case (.home, true):
            return "Reconnecting… last updated \(time)"
        case (.home, false):
            let agreement = monitor.lastData?.airQualityReading?.channelsAgree == false
                ? "sensor channels disagree" : "sensor channels agree"
            return "Updated \(time) · \(agreement)"
        default:
            return "Sensor unreachable"
        }
    }

    private var footerColor: Color {
        monitor.phase == .home && monitor.isStale
            ? Color(red: 1, green: 0.72, blue: 0.3).opacity(0.8)
            : .white.opacity(0.45)
    }

    private func saveHostname() {
        let trimmed = hostnameDraft
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        monitor.hostname = trimmed
        editingHostname = false
        monitor.hostnameDidChange()
    }
}
```

- [ ] **Step 2: Use it in the app**

In `PurpleAirBar/PurpleAirBarApp.swift`, replace the placeholder content closure:

```swift
        MenuBarExtra {
            PanelView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
```

- [ ] **Step 3: Build**

Run the Mac build command → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add PurpleAirBar
git commit -m "feat: living-wallpaper panel with footer controls"
```

---

### Task 7: End-to-end verification on this Mac

**Files:** none committed (screenshots to scratchpad); fix-forward small defects as follow-up commits.

- [ ] **Step 1: Full green sweep** — kit tests (`cd PurpleAirKit && swift test`), iOS build + smoke test, Mac build (all three Global Constraints commands).

- [ ] **Step 2: Live run** — launch the built `PurpleAir Bar.app`, wait 10 s. Attempt a menu bar screenshot: `screencapture -x /private/tmp/claude-501/-Users-shrisha-dev-purpleair-lan/4a6d99ca-454a-49a2-a36c-2c301ad39789/scratchpad/menubar.png` and READ it (crop attention to the top-right strip). If Screen Recording permission blocks capture (image shows wallpaper only / no menu bar), note it and fall back to asking the user to eyeball. Expected: `● <AQI>` next to the clock.

- [ ] **Step 3: Idle-cost sample** — after ≥3 minutes running: `ps -o %cpu=,rss= -p $(pgrep -f "PurpleAir Bar.app/Contents/MacOS")` → expect `0.0` CPU (or ≤0.1) and modest RSS.

- [ ] **Step 4: Ghost test** — `defaults write com.sr.PurpleAir-Bar sensorHostname nonexistent.invalid`, relaunch the app, wait ~15 s → label should be the dim ghost glyph (screenshot again if possible). Restore: `defaults write com.sr.PurpleAir-Bar sensorHostname purpleair.lan`, relaunch, confirm dot returns.

- [ ] **Step 5: Report** — verdicts per step, screenshots, any visual defects (fix-forward as small commits).

---

## Self-review notes

- Spec coverage: monorepo (T1–T2 + workspace in T3), policy (T4 §3.1), monitor + energy contract (T5 §3.2), label (T5 §3.3), panel home/away/footer (T6 §3.4), out-of-scope respected, verification (T7 §5). ✔
- Spec deviation, deliberate: `panelOpened()` does not wrap the probe in `ProcessInfo.beginActivity` — the app is processing user events at that moment (panel open) so it is not napping; the assertion would be pure ceremony. ✔
- Type consistency: `ReachabilityPolicy.Phase/Event/Action` names match across T4/T5; `SensorMonitor` published names match T5/T6; kit public API in T1 matches every later use. ✔
