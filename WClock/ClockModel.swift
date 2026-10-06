import SwiftUI
import CoreLocation
import os

@MainActor
final class ClockModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var weather: WeatherSnapshot?
    /// What's actually shown: the chosen appearance, or sunrise/sunset when set to auto.
    @Published private(set) var isNight = false
    @Published var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance); updateMode() }
    }
    @Published var dimAtNight: Bool {
        didSet { defaults.set(dimAtNight, forKey: Key.dimAtNight); updateBrightness() }
    }
    @Published var unit: TempUnit {
        didSet { defaults.set(unit.rawValue, forKey: Key.unit) }
    }

    private enum Key {
        static let appearance = "appearance", dimAtNight = "dimAtNight", unit = "unit"
        static let weather = "weather", lat = "lat", lon = "lon"
    }
    private static let refreshInterval: TimeInterval = 15 * 60
    private static let retryInterval: TimeInterval = 2 * 60
    /// Moving farther than this (metres) is worth a fresh weather lookup.
    private static let significantMove: CLLocationDistance = 5_000
    private static let log = Logger(subsystem: "com.jacobmoe.wclock", category: "weather")

    private let defaults = UserDefaults.standard
    private let manager = CLLocationManager()
    private let dimmer = ScreenDimmer()

    private var coordinate: CLLocationCoordinate2D?
    private var isLocating = false
    /// Most recent weather, kept even when too old to show: its sunrise/sunset still tell us day from night.
    private var savedWeather: WeatherSnapshot?
    private var weatherCoordinate: CLLocationCoordinate2D?
    private var fetchTask: Task<Void, Never>?
    private var nextRefresh = Date.distantPast
    private var timer: Timer?
    private var boosted = false
    private var boostTask: Task<Void, Never>?

    override init() {
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .auto
        dimAtNight = defaults.object(forKey: Key.dimAtNight) as? Bool ?? true
        unit = TempUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .localeDefault
        savedWeather = defaults.data(forKey: Key.weather).flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
        if defaults.object(forKey: Key.lat) != nil {
            coordinate = .init(latitude: defaults.double(forKey: Key.lat), longitude: defaults.double(forKey: Key.lon))
        }
        super.init()
        weather = savedWeather.flatMap { $0.isFresh ? $0 : nil }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        updateMode()
    }

    // MARK: Lifecycle

    /// Call when the app becomes active.
    func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()  // the authorization callback requests the location
        } else {
            requestLocation()
        }
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Call when the app goes inactive/background.
    func stop() {
        timer?.invalidate()
        boostTask?.cancel()
        boosted = false
        dimmer.setDimmed(false)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func tick() {
        if let w = weather, !w.isFresh { weather = nil }
        refreshWeatherIfDue()
        updateMode()
    }

    // MARK: Day / night and brightness

    private func updateMode() {
        let night: Bool
        switch appearance {
        case .day: night = false
        case .night: night = true
        case .auto:
            if let sun = weather ?? savedWeather {
                night = sun.isNight()
            } else {
                let m = Date.now.minuteOfDay
                night = m < WeatherSnapshot.fallbackSunrise || m >= WeatherSnapshot.fallbackSunset
            }
        }
        if night != isNight { withAnimation(.easeInOut(duration: 3)) { isNight = night } }
        updateBrightness()
    }

    private func updateBrightness() {
        dimmer.setDimmed(isNight && dimAtNight && !boosted)
    }

    /// Briefly restores full brightness (e.g. to read the screen from across the room).
    func toggleBoost() {
        boostTask?.cancel()
        boosted.toggle()
        updateBrightness()
        guard boosted else { return }
        boostTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            boosted = false
            updateBrightness()
        }
    }

    // MARK: Weather

    /// True when the data is old, or the iPad has moved far from where the weather was fetched.
    private var weatherIsDue: Bool {
        guard coordinate != nil else { return false }
        if Date.now >= nextRefresh { return true }
        guard let used = weatherCoordinate, let now = coordinate else { return false }
        return CLLocation(latitude: used.latitude, longitude: used.longitude)
            .distance(from: CLLocation(latitude: now.latitude, longitude: now.longitude)) > Self.significantMove
    }

    private func refreshWeatherIfDue() {
        guard fetchTask == nil, weatherIsDue, let c = coordinate else { return }
        fetchTask = Task {
            do {
                var w = try await WeatherProvider.fetch(latitude: c.latitude, longitude: c.longitude)
                w.fetchedAt = .now
                weather = w
                savedWeather = w
                weatherCoordinate = c
                nextRefresh = .now + Self.refreshInterval
                defaults.set(try? JSONEncoder().encode(w), forKey: Key.weather)
                fetchTask = nil
                updateMode()
                refreshWeatherIfDue()  // picks up a location change that happened mid-fetch
            } catch {
                Self.log.error("Weather fetch failed: \(String(describing: error))")
                nextRefresh = .now + Self.retryInterval
                fetchTask = nil
            }
        }
    }

    // MARK: Location

    private func requestLocation() {
        guard !isLocating else { return }
        isLocating = true
        manager.requestLocation()
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let c = locs.last?.coordinate else { return }
        Task { @MainActor in
            isLocating = false
            coordinate = c
            defaults.set(c.latitude, forKey: Key.lat)
            defaults.set(c.longitude, forKey: Key.lon)
            refreshWeatherIfDue()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isLocating = false
            Self.log.error("Location failed: \(String(describing: error))")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways else { return }
        Task { @MainActor in requestLocation() }
    }
}
