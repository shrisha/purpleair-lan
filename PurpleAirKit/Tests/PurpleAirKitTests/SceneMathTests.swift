// PurpleAir LANTests/SceneMathTests.swift
import Testing
import Foundation
@testable import PurpleAirKit

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
