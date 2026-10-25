import Foundation
import Testing
@testable import EczemaKit

/// Open-Meteo parsing (fixtures shaped like the real 2026-10 responses for Berkeley, CA).
@Suite struct EnvironmentTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }()
    /// 2026-10-23 15:40 local (UTC-7).
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15, minute: 40))! }

    func hourly(_ days: [String], _ value: (Int, Int) -> String) -> (times: String, values: String) {
        var t: [String] = [], v: [String] = []
        for (d, day) in days.enumerated() {
            for h in 0..<24 {
                t.append("\"\(day)T\(String(format: "%02d", h)):00\"")
                v.append(value(d, h))
            }
        }
        return (t.joined(separator: ","), v.joined(separator: ","))
    }

    var forecast: Data {
        let days = ["2026-10-22", "2026-10-23"]
        let hum = hourly(days) { d, _ in d == 0 ? "28" : "60" }
        let temp = hourly(days) { d, h in d == 0 ? "10" : String(10 + h % 4) }
        return """
        {"latitude":37.877266,"longitude":-122.27561,"utc_offset_seconds":-25200,"timezone":"America/Los_Angeles",
         "current":{"time":"2026-10-23T15:30","interval":900,"temperature_2m":18.0,"relative_humidity_2m":77},
         "hourly":{"time":[\(hum.times)],"temperature_2m":[\(temp.values)],"relative_humidity_2m":[\(hum.values)]}}
        """.data(using: .utf8)!
    }

    func air(pollen: Bool) -> Data {
        let days = ["2026-10-22", "2026-10-23"]
        let aqi = hourly(days) { d, h in d == 0 ? "\(40 + h)" : "30" }
        let grass = hourly(days) { _, h in pollen ? "\(h)" : "null" }
        let none = hourly(days) { _, _ in pollen ? "0.0" : "null" }
        let current = pollen ? "\"grass_pollen\":20.0,\"birch_pollen\":0.0" : "\"grass_pollen\":null,\"birch_pollen\":null"
        return """
        {"latitude":37.9,"longitude":-122.3,"utc_offset_seconds":-25200,
         "current":{"time":"2026-10-23T15:00","interval":3600,"us_aqi":44,\(current),"alder_pollen":null,"mugwort_pollen":null,"olive_pollen":null,"ragweed_pollen":null},
         "hourly":{"time":[\(aqi.times)],"us_aqi":[\(aqi.values)],"alder_pollen":[\(none.values)],"birch_pollen":[\(none.values)],
                   "grass_pollen":[\(grass.values)],"mugwort_pollen":[\(none.values)],"olive_pollen":[\(none.values)],"ragweed_pollen":[\(none.values)]}}
        """.data(using: .utf8)!
    }

    @Test func currentAndDaily() throws {
        let r = try OpenMeteoClient.parse(forecast: forecast, airQuality: air(pollen: false), now: now, calendar: cal)
        #expect(r.current.humidityPct == 77)
        #expect(r.current.tempC == 18)
        #expect(r.current.aqi == 44)
        #expect(r.current.pollen == .unknown)          // US: no pollen model
        #expect(r.daily.count == 2)
        let yesterday = try #require(r.day(cal.date(from: DateComponents(year: 2026, month: 10, day: 22))!, calendar: cal))
        #expect(yesterday.humidityPct == 28)
        #expect(yesterday.isDry)
        #expect(yesterday.tempC == 10)
        #expect(yesterday.aqi == 63)                   // worst hour of the day (40 + 23)
        let today = try #require(r.daily.last)
        #expect(!today.isDry)
        #expect(cal.isDate(today.time, inSameDayAs: now))
    }

    @Test func futureHoursAreIgnored() throws {
        let r = try OpenMeteoClient.parse(forecast: forecast, airQuality: nil, now: now, calendar: cal)
        // Today's temperature mean only uses 00:00...15:00 (16 hours of 10,11,12,13 repeating).
        let today = try #require(r.daily.last)
        #expect(today.tempC == 11.5)
        #expect(r.current.aqi == nil)
        #expect(r.current.pollen == .unknown)
    }

    @Test func pollenWhereCovered() throws {
        let r = try OpenMeteoClient.parse(forecast: forecast, airQuality: air(pollen: true), now: now, calendar: cal)
        #expect(r.current.pollen == .moderate)          // 20 grains/m³
        #expect(r.daily.first?.pollen == .moderate)    // max 23 grains/m³
        #expect(PollenLevel.from(grainsPerM3: 0) == PollenLevel.none)
        #expect(PollenLevel.from(grainsPerM3: nil) == .unknown)
        #expect(PollenLevel.from(grainsPerM3: 200) == .high)
    }

    @Test func urls() {
        let f = OpenMeteoClient.forecastURL(latitude: 37.87, longitude: -122.27, pastDays: 13).absoluteString
        #expect(f.contains("relative_humidity_2m"))
        #expect(f.contains("past_days=13"))
        let a = OpenMeteoClient.airQualityURL(latitude: 37.87, longitude: -122.27, pastDays: 200).absoluteString
        #expect(a.contains("us_aqi"))
        #expect(a.contains("past_days=92"))
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) { try OpenMeteoClient.parse(forecast: Data("{}".utf8), airQuality: nil) }
    }
}
