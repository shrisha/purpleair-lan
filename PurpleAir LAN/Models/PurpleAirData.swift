import Foundation
import SwiftUI

// MARK: - PurpleAir Sensor Data Model
struct PurpleAirData: Codable {
    // Basic sensor information
    let sensorId: String?
    let dateTime: String?
    let geo: String?
    
    // Environmental data - the main values we'll display
    let currentTempF: Double?
    let currentHumidity: Double?
    let pressure: Double?
    let pm25AqiB: Int?
    let p25AqicB: String? // RGB color string for AQI background

    // Raw PM2.5 (CF=1) per laser channel — inputs to the EPA correction
    let pm25CF1A: Double?
    let pm25CF1B: Double?

    // Sensor location (drives the solar model)
    let latitude: Double?
    let longitude: Double?

    // Additional sensor data (available for future features)
    let rssi: Int?
    let uptime: Int?
    let version: String?
    let place: String?
    let ssid: String?
    let wlstate: String?
    
    // Coding keys to match the JSON response format
    enum CodingKeys: String, CodingKey {
        case sensorId = "SensorId"
        case dateTime = "DateTime"
        case geo = "Geo"
        case currentTempF = "current_temp_f"
        case currentHumidity = "current_humidity"
        case pressure = "pressure"
        case pm25AqiB = "pm2.5_aqi_b"
        case p25AqicB = "p25aqic_b"
        case pm25CF1A = "pm2_5_cf_1"
        case pm25CF1B = "pm2_5_cf_1_b"
        case latitude = "lat"
        case longitude = "lon"
        case rssi = "rssi"
        case uptime = "uptime"
        case version = "version"
        case place = "place"
        case ssid = "ssid"
        case wlstate = "wlstate"
    }
}

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