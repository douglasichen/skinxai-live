import Foundation

// MARK: - Model

/// Weather and air around the user at one moment (or averaged over one day).
public struct EnvironmentReading: Codable, Hashable, Sendable {
    public var time: Date
    /// Outdoor relative humidity in percent.
    public var humidityPct: Double?
    public var tempC: Double?
    /// US AQI (0–500).
    public var aqi: Int?
    /// `.unknown` where the pollen model has no coverage (Open-Meteo pollen is Europe only).
    public var pollen: PollenLevel

    public init(time: Date, humidityPct: Double?, tempC: Double?, aqi: Int?, pollen: PollenLevel) {
        self.time = time; self.humidityPct = humidityPct; self.tempC = tempC; self.aqi = aqi; self.pollen = pollen
    }

    /// Below this outdoor humidity the app calls the air "dry".
    public static let dryHumidityPct: Double = 35
    public var isDry: Bool { (humidityPct ?? 100) < Self.dryHumidityPct }
}

public struct EnvironmentReport: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var fetchedAt: Date
    public var current: EnvironmentReading
    /// One reading per calendar day (time = start of that day), oldest first, days so far only.
    public var daily: [EnvironmentReading]

    public init(latitude: Double, longitude: Double, fetchedAt: Date, current: EnvironmentReading, daily: [EnvironmentReading]) {
        self.latitude = latitude; self.longitude = longitude; self.fetchedAt = fetchedAt; self.current = current; self.daily = daily
    }

    public func day(_ date: Date, calendar: Calendar = .current) -> EnvironmentReading? {
        daily.first { calendar.isDate($0.time, inSameDayAs: date) }
    }
}

public extension PollenLevel {
    /// Rough level from the highest species count in grains/m³ (nil = no coverage).
    static func from(grainsPerM3 value: Double?) -> PollenLevel {
        guard let value else { return .unknown }
        switch value {
        case ..<1: return .none
        case ..<15: return .low
        case ..<90: return .moderate
        default: return .high
        }
    }

    /// Ordering for "worst of the day".
    var rank: Int {
        switch self { case .unknown: -1; case .none: 0; case .low: 1; case .moderate: 2; case .high: 3 }
    }
}

// MARK: - Client

/// Open-Meteo weather + air-quality client (free, no API key). Network is optional: callers keep
/// their last values when this throws.
public struct OpenMeteoClient: Sendable {
    public enum Failure: Error { case http(Int), noData }

    public var session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    private static let pollenFields = ["alder_pollen", "birch_pollen", "grass_pollen", "mugwort_pollen", "olive_pollen", "ragweed_pollen"]

    public static func forecastURL(latitude: Double, longitude: Double, pastDays: Int) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", latitude)),
            .init(name: "longitude", value: String(format: "%.3f", longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m"),
            .init(name: "hourly", value: "temperature_2m,relative_humidity_2m"),
            .init(name: "past_days", value: String(max(0, min(pastDays, 92)))),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        return c.url!
    }

    public static func airQualityURL(latitude: Double, longitude: Double, pastDays: Int) -> URL {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        let fields = (["us_aqi"] + pollenFields).joined(separator: ",")
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", latitude)),
            .init(name: "longitude", value: String(format: "%.3f", longitude)),
            .init(name: "current", value: fields),
            .init(name: "hourly", value: fields),
            .init(name: "past_days", value: String(max(0, min(pastDays, 92)))),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
        ]
        return c.url!
    }

    /// Current conditions plus one reading per day for the last `pastDays` days (and today so far).
    /// Air quality is best effort: without it AQI is nil and pollen `.unknown`.
    public func report(latitude: Double, longitude: Double, pastDays: Int = 13, now: Date = Date(),
                       calendar: Calendar = .current) async throws -> EnvironmentReport {
        async let forecast = fetch(Self.forecastURL(latitude: latitude, longitude: longitude, pastDays: pastDays))
        async let air = fetchOptional(Self.airQualityURL(latitude: latitude, longitude: longitude, pastDays: pastDays))
        let forecastData = try await forecast
        let airData = await air
        return try Self.parse(forecast: forecastData, airQuality: airData, now: now, calendar: calendar)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("EczemaTwin/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
        return data
    }

    private func fetchOptional(_ url: URL) async -> Data? {
        try? await fetch(url)
    }

    // MARK: Parsing (pure, unit-tested)

    public static func parse(forecast: Data, airQuality: Data?, now: Date = Date(), calendar: Calendar = .current) throws -> EnvironmentReport {
        let f = try JSONDecoder().decode(ForecastJSON.self, from: forecast)
        let a = airQuality.flatMap { try? JSONDecoder().decode(AirJSON.self, from: $0) }
        let fClock = Clock(offset: f.utcOffsetSeconds)

        // Hourly samples so far, keyed by hour.
        struct Hour { var humidity: Double?; var temp: Double?; var aqi: Double?; var pollen: Double?; var hasPollen = false }
        var hours: [Date: Hour] = [:]
        if let h = f.hourly {
            for (i, t) in h.time.enumerated() {
                guard let date = fClock.date(t), date <= now else { continue }
                hours[date, default: Hour()].humidity = h.relativeHumidity2m?[omSafe: i] ?? nil
                hours[date, default: Hour()].temp = h.temperature2m?[omSafe: i] ?? nil
            }
        }
        if let a, let h = a.hourly {
            let aClock = Clock(offset: a.utcOffsetSeconds)
            for (i, t) in h.time.enumerated() {
                guard let date = aClock.date(t), date <= now else { continue }
                hours[date, default: Hour()].aqi = h.usAqi?[omSafe: i] ?? nil
                let pollen = h.pollen(at: i)
                hours[date, default: Hour()].pollen = pollen
                hours[date, default: Hour()].hasPollen = pollen != nil
            }
        }

        // Daily aggregates.
        let byDay = Dictionary(grouping: hours, by: { calendar.startOfDay(for: $0.key) })
        let daily: [EnvironmentReading] = byDay.keys.sorted().map { day in
            let samples = byDay[day]!.map(\.value)
            let hum = samples.compactMap(\.humidity)
            let temp = samples.compactMap(\.temp)
            let aqi = samples.compactMap(\.aqi)
            let pollen = samples.filter(\.hasPollen).compactMap(\.pollen)
            return EnvironmentReading(
                time: day,
                humidityPct: hum.isEmpty ? nil : (hum.reduce(0, +) / Double(hum.count)).rounded(),
                tempC: temp.isEmpty ? nil : ((temp.reduce(0, +) / Double(temp.count)) * 10).rounded() / 10,
                aqi: aqi.max().map { Int($0.rounded()) },
                pollen: pollen.isEmpty ? .unknown : PollenLevel.from(grainsPerM3: pollen.max()))
        }

        // Current conditions (fall back to today's aggregate).
        let today = daily.last { calendar.isDate($0.time, inSameDayAs: now) }
        let currentPollen: PollenLevel = {
            if let p = a?.current?.pollen { return PollenLevel.from(grainsPerM3: p) }
            return today?.pollen ?? .unknown
        }()
        let current = EnvironmentReading(
            time: f.current.flatMap { fClock.date($0.time) } ?? now,
            humidityPct: f.current?.relativeHumidity2m ?? today?.humidityPct,
            tempC: f.current?.temperature2m ?? today?.tempC,
            aqi: a?.current?.usAqi.map { Int($0.rounded()) } ?? today?.aqi,
            pollen: currentPollen)

        guard current.humidityPct != nil || current.tempC != nil || !daily.isEmpty else { throw Failure.noData }
        return EnvironmentReport(latitude: f.latitude, longitude: f.longitude, fetchedAt: now, current: current, daily: daily)
    }

    /// Open-Meteo local times ("2026-10-23T15:30") in the location's UTC offset.
    private struct Clock {
        let formatter: DateFormatter
        init(offset: Int) {
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        }
        func date(_ s: String) -> Date? { formatter.date(from: s) }
    }

    private struct ForecastJSON: Decodable {
        let latitude: Double
        let longitude: Double
        let utcOffsetSeconds: Int
        let current: Current?
        let hourly: Hourly?
        struct Current: Decodable {
            let time: String
            let temperature2m: Double?
            let relativeHumidity2m: Double?
            enum CodingKeys: String, CodingKey { case time, temperature2m = "temperature_2m", relativeHumidity2m = "relative_humidity_2m" }
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature2m: [Double?]?
            let relativeHumidity2m: [Double?]?
            enum CodingKeys: String, CodingKey { case time, temperature2m = "temperature_2m", relativeHumidity2m = "relative_humidity_2m" }
        }
        enum CodingKeys: String, CodingKey { case latitude, longitude, utcOffsetSeconds = "utc_offset_seconds", current, hourly }
    }

    private struct AirJSON: Decodable {
        let utcOffsetSeconds: Int
        let current: Current?
        let hourly: Hourly?
        struct Current: Decodable {
            let time: String
            let usAqi: Double?
            let alder, birch, grass, mugwort, olive, ragweed: Double?
            /// Highest species count, nil when the model has no coverage here.
            var pollen: Double? { [alder, birch, grass, mugwort, olive, ragweed].compactMap { $0 }.max() }
            enum CodingKeys: String, CodingKey {
                case time, usAqi = "us_aqi", alder = "alder_pollen", birch = "birch_pollen", grass = "grass_pollen"
                case mugwort = "mugwort_pollen", olive = "olive_pollen", ragweed = "ragweed_pollen"
            }
        }
        struct Hourly: Decodable {
            let time: [String]
            let usAqi: [Double?]?
            let alder, birch, grass, mugwort, olive, ragweed: [Double?]?
            func pollen(at i: Int) -> Double? {
                [alder, birch, grass, mugwort, olive, ragweed].compactMap { $0?[omSafe: i] ?? nil }.max()
            }
            enum CodingKeys: String, CodingKey {
                case time, usAqi = "us_aqi", alder = "alder_pollen", birch = "birch_pollen", grass = "grass_pollen"
                case mugwort = "mugwort_pollen", olive = "olive_pollen", ragweed = "ragweed_pollen"
            }
        }
        enum CodingKeys: String, CodingKey { case utcOffsetSeconds = "utc_offset_seconds", current, hourly }
    }
}

private extension Array {
    subscript(omSafe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
