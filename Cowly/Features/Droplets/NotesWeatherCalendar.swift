import AppKit
import CoreLocation
import EventKit
import Foundation
import Observation
import SwiftUI

// MARK: - Notes

struct QuickNote: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var createdAt: Date = .now
    var isDone: Bool = false
}

@MainActor
@Observable
final class NotesStore {
    static let shared = NotesStore()

    private(set) var notes: [QuickNote] = []
    var draft: String = ""

    private init() {
        notes = Disk.load([QuickNote].self, from: Paths.notesStore) ?? []
    }

    func commitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        notes.insert(QuickNote(text: text), at: 0)
        draft = ""
        Haptics.tap(.generic)
        persist()
    }

    func toggle(_ note: QuickNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].isDone.toggle()
        persist()
    }

    func remove(_ note: QuickNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    func clearCompleted() {
        notes.removeAll(where: \.isDone)
        persist()
    }

    private func persist() { Disk.save(notes, to: Paths.notesStore) }
}

// MARK: - Weather

struct WeatherSnapshot: Equatable, Sendable {
    var temperature: Double
    var apparent: Double
    var code: Int
    var isDay: Bool
    var high: Double
    var low: Double
    var place: String
    var updatedAt: Date

    /// Temperatures come back in Celsius; convert only for display.
    @MainActor
    func display(_ celsius: Double) -> String {
        let useF = Preferences.shared.useFahrenheit
        let value = useF ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var description: String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm, hail"
        default: "—"
        }
    }
}

/// Weather from Open-Meteo: no account, no key, no tracking.
@MainActor
@Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherStore()

    private(set) var snapshot: WeatherSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard refreshTimer == nil else { return }
        requestLocation()
        let timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestLocation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func requestLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            errorMessage = "Location access is off. Turn it on in System Settings › Privacy."
        default:
            locationManager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let authorized = status == .authorizedAlways || status == .authorized
        MainActor.assumeIsolated {
            if authorized { self.locationManager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        MainActor.assumeIsolated {
            Task { await self.fetch(for: coordinate) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            self.errorMessage = message
        }
    }

    private func fetch(for coordinate: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", lat)),
            .init(name: "longitude", value: String(format: "%.3f", lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,is_day,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1")
        ]
        guard let url = components.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let place = await reverseGeocode(coordinate) ?? "Nearby"
            snapshot = WeatherSnapshot(
                temperature: decoded.current.temperature_2m,
                apparent: decoded.current.apparent_temperature,
                code: decoded.current.weather_code,
                isDay: decoded.current.is_day == 1,
                high: decoded.daily.temperature_2m_max.first ?? 0,
                low: decoded.daily.temperature_2m_min.first ?? 0,
                place: place,
                updatedAt: .now
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.locality ?? placemarks?.first?.administrativeArea
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let is_day: Int
            let weather_code: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }
}

// MARK: - Calendar

struct AgendaEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let colorHex: String
    let calendarName: String

    var timeLabel: String {
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: start)
    }

    var isNow: Bool { start <= .now && end > .now }
    var minutesUntil: Int { max(0, Int(start.timeIntervalSinceNow / 60)) }
}

@MainActor
@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    private(set) var events: [AgendaEvent] = []
    private(set) var accessGranted = false
    private(set) var errorMessage: String?

    private let store = EKEventStore()
    private var timer: Timer?

    private init() {}

    func start() {
        Task { await requestAccess() }
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func requestAccess() async {
        do {
            accessGranted = try await store.requestFullAccessToEvents()
            if accessGranted { reload() } else { errorMessage = "Calendar access denied." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        guard accessGranted else { return }
        let start = Date.now
        let days = max(1, Preferences.shared.calendarDaysAhead)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .prefix(40)
            .map { event in
                AgendaEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    colorHex: NSColor(cgColor: event.calendar.cgColor)?.hexString ?? "#5A87FF",
                    calendarName: event.calendar.title
                )
            }
    }

    var next: AgendaEvent? { events.first { $0.end > .now } }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#5A87FF" }
        return String(
            format: "#%02X%02X%02X",
            Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255)
        )
    }
}
