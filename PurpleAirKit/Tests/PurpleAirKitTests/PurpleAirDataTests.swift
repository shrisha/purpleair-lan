import Testing
import Foundation
@testable import PurpleAirKit

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
