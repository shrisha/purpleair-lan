// PurpleAir LAN/Views/Scene/SolarModel.swift
import Foundation

/// Approximate solar position (NOAA simplified equations) driving the
/// scene's day/night blend. Falls back to a local-clock curve when the
/// sensor reports no coordinates.
public enum SolarModel {
    public static func factors(date: Date, latitude: Double?, longitude: Double?) -> (daylight: Double, twilight: Double) {
        guard let latitude, let longitude else { return clockFactors(date: date) }
        let elev = solarElevationDegrees(date: date, latitude: latitude, longitude: longitude)
        let daylight = smoothstep(-6, 12, elev)
        let twilight = exp(-pow(elev / 6, 2))
        return (daylight, twilight)
    }

    public static func solarElevationDegrees(date: Date, latitude: Double, longitude: Double) -> Double {
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
