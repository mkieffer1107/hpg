import CoreLocation
import UIKit

/// iOS suspends an app a few seconds after it leaves the screen, which would drop the SSH
/// connection and mean another password + Duo login. While enabled, this keeps the app running
/// in the background with the coarsest possible location updates (the same approach Blink Shell
/// uses). The blue location pill shows while it's active. Swiping the app away still ends it.
///
/// With "While Using" permission iOS only lets location updates *continue* in the background,
/// they can't be started there. So updates start while the app is on screen (as soon as a login
/// begins) and keep running until you disconnect; going to the background then just carries on.
@MainActor
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var activity: CLBackgroundActivitySession?
    private var wanted = false
    private(set) var running = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    var authorized: Bool {
        [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus)
    }

    var denied: Bool {
        [.denied, .restricted].contains(manager.authorizationStatus)
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// Whether the session should survive the background. Call while the app is on screen.
    func setWanted(_ on: Bool) {
        wanted = on
        if on { requestPermission(); startUpdates() } else { stopUpdates() }
    }

    /// Bridges the moment of leaving the screen (and covers the case where location isn't allowed:
    /// iOS then gives roughly 30 seconds, often enough to approve a Duo push and come back).
    func enteredBackground(force: Bool = false) {
        guard wanted || force, task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask { [weak self] in self?.endTask() }
    }

    func enteredForeground() { endTask() }

    private func startUpdates() {
        guard wanted, authorized, !running else { return }
        running = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        activity = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
    }

    private func stopUpdates() {
        endTask()
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        activity?.invalidate(); activity = nil
    }

    private func endTask() {
        if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.startUpdates() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
