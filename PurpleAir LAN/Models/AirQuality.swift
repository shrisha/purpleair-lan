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
