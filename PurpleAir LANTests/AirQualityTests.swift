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
@Test func channelsDisagree() { #expect(AirQuality.channelsAgree(1, 8) == false) }

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
