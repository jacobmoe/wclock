import Foundation
#if WEATHERKIT
import CoreLocation
import WeatherKit
#endif

extension Date {
    /// Minutes after local midnight.
    var minuteOfDay: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

struct WeatherSnapshot: Equatable, Codable {
    /// All temperatures are in Celsius; convert for display.
    var temperature: Double
    var high: Double
    var low: Double
    var symbol: String
    var summary: String
    /// Minutes after local midnight, so they stay usable on days after the fetch.
    var sunriseMinute: Int
    var sunsetMinute: Int
    var fetchedAt = Date.now

    static let fallbackSunrise = 7 * 60
    static let fallbackSunset = 19 * 60

    /// Recent enough to show. Older weather is hidden rather than shown out of date.
    var isFresh: Bool { Date.now.timeIntervalSince(fetchedAt) < 20 * 60 }

    func isNight(at date: Date = .now) -> Bool {
        let m = date.minuteOfDay
        return m < sunriseMinute || m >= sunsetMinute
    }
}

/// Credit that must be shown for the weather source (WeatherKit requires Apple's mark and a legal link).
struct WeatherAttribution {
    let name: String
    /// Logo for use on a dark background, if the provider requires one.
    let markURL: URL?
    let legalURL: URL
}

/// Weather from Apple WeatherKit when built with the WEATHERKIT flag (see project-weatherkit.yml),
/// otherwise from Open-Meteo (free, no API key). Apple's Weather app itself has no public API.
enum WeatherProvider {
    static func fetch(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        #if WEATHERKIT
        return try await fetchWeatherKit(latitude: latitude, longitude: longitude)
        #else
        return try await fetchOpenMeteo(latitude: latitude, longitude: longitude)
        #endif
    }

    static func attribution() async -> WeatherAttribution? {
        #if WEATHERKIT
        guard let a = try? await WeatherKit.WeatherService.shared.attribution else { return nil }
        return WeatherAttribution(name: a.serviceName, markURL: a.combinedMarkLightURL, legalURL: a.legalPageURL)
        #else
        return WeatherAttribution(name: "Open-Meteo.com", markURL: nil, legalURL: URL(string: "https://open-meteo.com/")!)
        #endif
    }

    #if WEATHERKIT
    private static func fetchWeatherKit(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        let (current, daily) = try await WeatherKit.WeatherService.shared.weather(
            for: CLLocation(latitude: latitude, longitude: longitude), including: .current, .daily)
        func deg(_ m: Measurement<UnitTemperature>) -> Double { m.converted(to: .celsius).value }
        let today = daily.forecast.first
        return WeatherSnapshot(
            temperature: deg(current.temperature),
            high: today.map { deg($0.highTemperature) } ?? deg(current.temperature),
            low: today.map { deg($0.lowTemperature) } ?? deg(current.temperature),
            symbol: current.symbolName,
            summary: current.condition.description,
            sunriseMinute: today?.sun.sunrise?.minuteOfDay ?? WeatherSnapshot.fallbackSunrise,
            sunsetMinute: today?.sun.sunset?.minuteOfDay ?? WeatherSnapshot.fallbackSunset)
    }
    #endif

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]
            let sunset: [String]
        }
        let current: Current
        let daily: Daily
    }

    private static func fetchOpenMeteo(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)
        let (symbol, summary) = describe(code: r.current.weather_code, isDay: r.current.is_day == 1)
        return WeatherSnapshot(
            temperature: r.current.temperature_2m,
            high: r.daily.temperature_2m_max.first ?? 0,
            low: r.daily.temperature_2m_min.first ?? 0,
            symbol: symbol,
            summary: summary,
            sunriseMinute: minuteOfDay(r.daily.sunrise.first) ?? WeatherSnapshot.fallbackSunrise,
            sunsetMinute: minuteOfDay(r.daily.sunset.first) ?? WeatherSnapshot.fallbackSunset)
    }

    /// Parses "2026-10-06T07:12" (already in the location's local time).
    private static func minuteOfDay(_ s: String?) -> Int? {
        guard let t = s?.split(separator: "T").last else { return nil }
        let p = t.split(separator: ":")
        guard p.count >= 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    private static func describe(code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0: return (isDay ? "sun.max" : "moon.stars", "Clear")
        case 1: return (isDay ? "sun.max" : "moon", "Mostly clear")
        case 2: return (isDay ? "cloud.sun" : "cloud.moon", "Partly cloudy")
        case 3: return ("cloud", "Overcast")
        case 45, 48: return ("cloud.fog", "Fog")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle", "Drizzle")
        case 61, 63, 65, 66, 67: return ("cloud.rain", "Rain")
        case 71, 73, 75, 77: return ("cloud.snow", "Snow")
        case 80, 81, 82: return ("cloud.heavyrain", "Showers")
        case 85, 86: return ("cloud.snow", "Snow showers")
        case 95, 96, 99: return ("cloud.bolt.rain", "Thunderstorm")
        default: return ("cloud", "—")
        }
    }
}
