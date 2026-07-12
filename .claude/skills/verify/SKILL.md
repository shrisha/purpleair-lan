---
name: verify
description: Build, install, and drive PurpleAir LAN in the iOS simulator to verify changes at the UI surface
---

# Verifying PurpleAir LAN

## Build (simulator)

```bash
xcodebuild -project "PurpleAir LAN.xcodeproj" -scheme "PurpleAir LAN" \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath <scratch>/dd build
```

App lands at `<scratch>/dd/Build/Products/Debug-iphonesimulator/PurpleAir LAN.app`.
Bundle ID: `com.sr.PurpleAir-LAN`.

## Run

```bash
xcrun simctl boot "iPhone 17 Pro" ; open -a Simulator   # "Booted" error = already up
xcrun simctl install booted "<path>/PurpleAir LAN.app"
xcrun simctl launch booted com.sr.PurpleAir-LAN
xcrun simctl io booted screenshot out.png
```

## Flows worth driving

- Fresh install → ConfigurationView (setup screen). Saved hostname → DashboardView directly.
- The sensor at `http://purpleair.lan/json?live=true` is reachable from this Mac
  (simulator shares host network) — dashboard loading live data proves the HTTP/ATS path.

## Gotchas

- Hostname persists in `@AppStorage("sensorHostname")`. `simctl spawn booted defaults
  delete` does NOT clear it (cfprefsd caches; domain lives in the app container).
  To force the setup screen, `simctl uninstall` + reinstall.
- To seed a hostname without UI typing: terminate app, then
  `plutil -replace sensorHostname -string <value>
  "$(xcrun simctl get_app_container booted com.sr.PurpleAir-LAN data)/Library/Preferences/com.sr.PurpleAir-LAN.plist"`,
  relaunch.
- No cliclick / no assistive access for osascript in this environment — simulator
  taps/typing can't be scripted directly. A `PurpleAir LANUITests` UI-test target
  exists (filesystem-synchronized, no sources on disk yet); create sources under
  `PurpleAir LANUITests/` if a real UI driver is ever needed.
- ATS: Info.plist is `PurpleAir-LAN-Info.plist` at repo root; only
  `NSAllowsArbitraryLoads` — adding narrower ATS keys makes iOS ignore it.
