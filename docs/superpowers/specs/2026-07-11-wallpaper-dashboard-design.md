# PurpleAir LAN — Living-Wallpaper Dashboard Redesign (Approach A)

**Date:** 2026-07-11
**Status:** Draft for review
**Interactive mockup:** https://claude.ai/code/artifact/86df246b-22a2-4169-a867-a11c487b9fb2

## 1. Vision

Replace the four-tile dashboard with a full-bleed ambient scene in the iOS Weather
app's design language. The wallpaper *is* the metric: the background palette follows
the EPA AQI band, its brightness and warmth follow the sun, and drifting haze motes
thicken with PM2.5. A huge thin AQI numeral with the temperature beside it floats
directly on the scene; three frosted-glass cards carry the detail. The app behaves
like an ambient display: screen stays awake, chrome fades when idle.

## 2. Data pipeline (new `Models/AirQuality.swift`, pure functions)

All numbers shown to the user are corrected per EPA/PurpleAir guidance. Input is the
existing `/json` response (switch the dashboard fetch from `?live=true` to plain
`/json` — the firmware's 2-minute average is the right smoothing for an ambient
display; the setup screen's connection test may keep `live=true`).

1. **PM2.5 channel merge:** decode `pm2_5_cf_1` and `pm2_5_cf_1_b`; use the A/B mean.
   QC per EPA: channels *agree* when |A−B| < 5 µg/m³ or relative difference < 70%.
   Disagreement → still show the mean but flag low confidence in the footer
   ("sensor channels disagree"). Single-channel sensors (missing `_b`) use channel A.
2. **EPA (Barkjohn 2021 + Fire & Smoke extension) correction**, RH = raw
   `current_humidity` clamped 0–100, PA = merged cf_1, result clamped ≥ 0:
   - PA < 30: `0.524·PA − 0.0862·RH + 5.75`
   - 30 ≤ PA < 50: `(0.786·w + 0.524·(1−w))·PA − 0.0862·RH + 5.75`, `w = PA/20 − 1.5`
   - 50 ≤ PA < 210: `0.786·PA − 0.0862·RH + 5.75`
   - 210 ≤ PA < 260: blend to the quadratic with `w = PA/50 − 4.2`:
     `(0.69·w + 0.786·(1−w))·PA − 0.0862·RH·(1−w) + 2.966·w + 5.75·(1−w) + 8.84e−4·PA²·w`
   - PA ≥ 260: `2.966 + 0.69·PA + 8.84e−4·PA²`
3. **AQI (May-2024 EPA breakpoints)** — truncate concentration to 0.1, linear
   interpolation, cap 500. Do NOT use the firmware's `pm2.5_aqi_b` (predates the
   2024 revision).

   | Category | AQI | PM2.5 µg/m³ | EPA color |
   |---|---|---|---|
   | Good | 0–50 | 0.0–9.0 | `#00E400` |
   | Moderate | 51–100 | 9.1–35.4 | `#FFFF00` |
   | Unhealthy for Sensitive Groups | 101–150 | 35.5–55.4 | `#FF7E00` |
   | Unhealthy | 151–200 | 55.5–125.4 | `#FF0000` |
   | Very Unhealthy | 201–300 | 125.5–225.4 | `#8F3F97` |
   | Hazardous | 301–500 | 225.5+ | `#7E0023` |

4. **Temperature:** display `current_temp_f − 8` (documented board self-heating).
   **Humidity:** display `current_humidity + 4`, clamped 0–100.
   **Dew point:** recompute from corrected T/RH via Magnus (ignore the sensor's
   `current_dewpoint_f`, which is derived from the biased raw values).
5. **Pressure trend** (new `Services/PressureHistoryStore.swift`): persist
   (timestamp, hPa) samples in UserDefaults as a pruned ring buffer (~3.5 h window).
   3-hour delta → `falling` (≤ −1 hPa), `steady` (±1), `rising` (≥ +1); ±3 hPa/3 h
   reads "rapidly" in the footnote.
6. Health guidance strings per category (AirNow wording, lightly shortened for the
   card footnote — see mockup).

Unit tests cover: breakpoint edges (9.0→50, 9.1→51, 500 cap), correction pieces and
their seams (PA = 30, 50, 210, 260), A/B QC rules, Magnus dew point, trend
thresholds.

## 3. Scene engine (`Views/Scene/AmbientSceneView.swift`)

- **Inputs:** AQI category index (0–5), corrected PM2.5, clock time; sensor `lat`/
  `lon` (already in the JSON) feed a small solar-elevation approximation for
  daylight/twilight factors, falling back to fixed hours (dawn ≈ 6, dusk ≈ 19) if
  absent.
- **Base layer:** iOS 18 `MeshGradient` (3×3). Edge points pinned; two interior
  points drift with sin/cos of a slowed clock (`t/17`, `t/29`) inside
  `TimelineView(.animation(minimumInterval: 1/20))`. Colors = band palette (the six
  day/night palettes in the mockup source are the spec) blended day↔night by
  daylight factor, with a warm `#FF7A3C` tint injected at the horizon stops during
  twilight.
- **Particle layer:** `Canvas` in the same TimelineView. Haze motes: count =
  `clamp((pm25 − 5)/150, 0, 1) × 90`, soft radial blobs, slow horizontal drift,
  tone shifts warm-gray → amber → oxblood with the band. Stars: only when daylight
  factor < 0.18 AND AQI ≤ 100; ~70 points with sine twinkle.
- **Performance:** `.drawingGroup()` on the scene layer only (never on material
  cards); no animated blurs; palette changes crossfade with
  `withAnimation(.easeInOut(duration: 2))`.
- Whole screen forced `.environment(\.colorScheme, .dark)`.

## 4. Layout & typography (hero + cards)

Weather-app conventions, content floats on the scene (`.ignoresSafeArea()`):

- **Hero** (centered, upper ~40%): caption from the sensor's `place` field
  uppercased, e.g. `OUTSIDE` (12 pt semibold, tracking 0.14 em, white 0.62;
  omitted if absent) → station name from `Geo` (27 pt regular) → AQI
  numeral (SF Pro **thin**, ~110–122 pt, with a small `AQI` unit at 30 pt light) →
  category word (21 pt semibold, white 0.9) → temp line: `76° · Dew point 54°`
  (20 pt medium; the dot-separated tail at white 0.6). Values animate with
  `.contentTransition(.numericText())`.
- **Cards** (2-column `LazyVGrid`, 8 pt gaps, 16 pt margins,
  `RoundedRectangle(cornerRadius: 22, style: .continuous)`,
  `.ultraThinMaterial` + 0.5 pt white-0.14 inner hairline; headers 12 pt semibold
  uppercase white 0.62 with 13 pt SF Symbol; every card ends in a plain-language
  footnote sentence):
  1. **PM2.5 card** (full width): corrected µg/m³ value (30 pt medium) + unit
     caption "µg/m³ · EPA corrected"; the EPA gradient capsule (5 pt tall, official
     band colors, stops proportional to AQI span 0–500) with a 9 pt white dot at
     `AQI/500`; health-guidance footnote.
  2. **Humidity** (square): corrected % (30 pt), comfort word (Dry < 30,
     Comfortable 30–60, Humid > 60), footnote "The dew point is N° right now."
  3. **Pressure** (square): 270°-style arc gauge (hairline track white 0.22, white
     progress arc + dot), trend glyph (`arrow.up`/`equal`-style), value in hPa,
     footnote "Rising/Steady/Falling over the last 3 hours."
- **Footer caption** (11.5 pt, white 0.45): `Updated 6:32 PM · sensor channels
  agree` (or `· sensor channels disagree` on QC failure).

## 5. Ambient behavior (chrome)

- `UIApplication.shared.isIdleTimerDisabled = true` while the dashboard is active
  (set on scene-active, cleared on background).
- `.statusBarHidden(false)` (keep the clock — it's part of the wallpaper feel),
  `.persistentSystemOverlays(.hidden)`.
- Refresh + settings buttons top-right, no navigation bar. After 5 s without
  touches they fade to opacity 0 (2 s ease); any tap on the screen restores them
  and restarts the timer. Pull-to-refresh stays.
- Auto-refresh stays at 30 s; new data crossfades (no snap).

## 6. States

- **First load:** neutral Good-band night palette at low brightness + existing
  WeatherSpinner + "Checking sensor…".
- **Refresh failure with cached data:** keep showing last data; footer swaps to
  `Reconnecting… last updated 6:32 PM` (amber-tinted); scene dims ~10%. Retries on
  the normal 30 s cadence.
- **Failure with no data:** dim scene + message + Try Again + gear access
  (reworked current errorView, restyled to the new language).
- Missing individual fields render `—` and drop their footnote.

## 7. Files

| File | Change |
|---|---|
| `Models/AirQuality.swift` | new — corrections, AQI, categories, colors, health text, comfort/dew-point/trend logic |
| `Models/PurpleAirData.swift` | decode `pm2_5_cf_1`, `pm2_5_cf_1_b`, `lat`, `lon`; drop reliance on `pm2.5_aqi_b`/`p25aqic_b` |
| `Services/PurpleAirService.swift` | fetch `/json` (not `live=true`) for dashboard |
| `Services/PressureHistoryStore.swift` | new — persisted samples + 3 h trend |
| `Views/Scene/AmbientSceneView.swift` | new — mesh + particles |
| `Views/DashboardView.swift` | rewrite — hero, cards, chrome fade, states |
| `Views/Components/DataTile.swift` | delete (superseded) |
| `PurpleAir LANTests` | new unit tests for `AirQuality` + trend store |

Setup/configuration flow is unchanged.

## 8. Out of scope (noted for later)

NowCast rolling AQI, StandBy/WidgetKit companion, red-shift night mode, historical
charts, multi-sensor support.
