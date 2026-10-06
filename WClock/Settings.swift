import Foundation

enum Appearance: String, CaseIterable, Identifiable {
    case auto, day, night
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TempUnit: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var title: String { self == .fahrenheit ? "°F" : "°C" }

    static var localeDefault: TempUnit { Locale.current.measurementSystem == .us ? .fahrenheit : .celsius }

    /// Whole degrees in this unit, from Celsius.
    func degrees(fromCelsius c: Double) -> Int {
        Int((self == .fahrenheit ? c * 9 / 5 + 32 : c).rounded())
    }
}
