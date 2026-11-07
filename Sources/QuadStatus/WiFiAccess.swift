import AppKit
import CoreLocation

/// What's left of a Wi-Fi menu: the connected network's name and a way into
/// Wi-Fi Settings. Joining networks from a third-party app needs an administrator
/// (airportd's requireAdministratorForAssociation), so switching is left to the
/// system.
///
/// The name (SSID) is only visible to apps with Location access, so the menu asks
/// for it once. The location itself is never read.
final class WiFiAccess: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
    }

    var allowed: Bool {
        [.authorizedAlways, .authorized].contains(location.authorizationStatus)
    }

    /// Call when the menu opens; prompts only the first time.
    func requestIfNeeded() {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    @objc func openWiFiSettings() {
        open("x-apple.systempreferences:com.apple.wifi-settings-extension")
    }

    @objc func openLocationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
