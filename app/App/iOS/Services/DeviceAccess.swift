import Foundation
import CoreLocation
import UserNotifications
import UIKit

/// Permissions in one place (onboarding page 3, Settings): Apple Health, location (when in use),
/// notifications. Every request is optional; nothing in the app needs them to work.
@MainActor
final class DeviceAccess: NSObject, ObservableObject {
    enum State: Equatable {
        /// `asked`: the request was answered but nothing proves access yet (Apple Health only:
        /// it never tells apps what was allowed, so this turns `on` once a query returns data).
        case notAsked, asked, on, off, unavailable
    }

    @Published private(set) var health: State = .notAsked
    @Published private(set) var location: State = .notAsked
    @Published private(set) var notifications: State = .notAsked

    let healthReader = HealthReader()
    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        location = Self.state(manager.authorizationStatus)
        if !HealthReader.isAvailable { health = .unavailable }
    }

    func refresh() async {
        if HealthReader.isAvailable {
            if !(await healthReader.wasAsked()) {
                health = .notAsked
            } else {
                health = await healthReader.returnsSamples() ? .on : .asked
            }
        }
        #if DEBUG
        // `-healthState asked|on|off` (screenshots: a script can't answer the Health sheet).
        switch UserDefaults.standard.string(forKey: "healthState") {
        case "asked": health = .asked
        case "on": health = .on
        case "off": health = .off
        default: break
        }
        #endif
        location = Self.state(manager.authorizationStatus)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = switch settings.authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .off
        default: .on
        }
    }

    func requestHealth() async {
        await healthReader.requestAccess()
        await refresh()
    }

    func requestLocation() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if location == .off {
            openSettings()
        }
    }

    func requestNotifications() async {
        if notifications == .off { openSettings(); return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// The Health app, where read access is managed (falls back to this app's Settings page).
    func openHealth() {
        guard let url = URL(string: "x-apple-health://") else { openSettings(); return }
        UIApplication.shared.open(url) { [weak self] opened in
            if !opened { Task { @MainActor in self?.openSettings() } }
        }
    }

    // MARK: Location fix

    /// Last coarse position (rounded to ~1 km) so weather works offline / before a new fix.
    var cachedCoordinate: CLLocationCoordinate2D? {
        let d = UserDefaults.standard
        guard d.object(forKey: Self.latKey) != nil else { return nil }
        return CLLocationCoordinate2D(latitude: d.double(forKey: Self.latKey), longitude: d.double(forKey: Self.lonKey))
    }

    /// One coarse location fix (nil without permission, on error, or after 15 s).
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        guard location == .on else { return cachedCoordinate }
        let fix: CLLocation? = await withCheckedContinuation { cont in
            fixWaiters.append(cont)
            if fixWaiters.count == 1 { manager.requestLocation() }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.finishFix(nil)
            }
        }
        guard let fix else { return cachedCoordinate }
        let lat = (fix.coordinate.latitude * 100).rounded() / 100
        let lon = (fix.coordinate.longitude * 100).rounded() / 100
        UserDefaults.standard.set(lat, forKey: Self.latKey)
        UserDefaults.standard.set(lon, forKey: Self.lonKey)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func finishFix(_ location: CLLocation?) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        waiters.forEach { $0.resume(returning: location) }
    }

    private static let latKey = "et.lastLat", lonKey = "et.lastLon"

    private static func state(_ s: CLAuthorizationStatus) -> State {
        switch s {
        case .notDetermined: .notAsked
        case .authorizedWhenInUse, .authorizedAlways: .on
        default: .off
        }
    }
}

extension DeviceAccess: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.location = DeviceAccess.state(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finishFix(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishFix(nil) }
    }
}
