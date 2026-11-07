import AppKit

/// NordVPN control through its URL scheme — the macOS app has no CLI and no
/// Shortcuts actions. Verified against NordVPN 10.12:
///   · nordvpn://connect?country=<ISO 3166 alpha-2> connects, or switches country
///     ("gb", not "uk" — "uk" falls back to a quick connect)
///   · there is no disconnect action, so that is left to the NordVPN window
enum NordVPN {
    static let bundleID = "com.nordvpn.macos"

    /// Countries offered in the menu. Override with
    /// `defaults write io.github.chocholous.quadstatus vpnCountries -array cz us de gb`
    private static let countriesKey = "vpnCountries"
    private static let defaultCountries = ["cz", "us", "de", "gb"]

    static var installed: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var countries: [String] {
        UserDefaults.standard.stringArray(forKey: countriesKey) ?? defaultCountries
    }

    /// Country of the last connection, from NordVPN's own preferences, where it
    /// is stored as "categoryCountry:cz:-:17:-". Only meaningful while a tunnel is up.
    static var lastCountry: String? {
        guard let key = UserDefaults(suiteName: bundleID)?.string(forKey: "lastConnectionPrimaryKey")
        else { return nil }
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count > 1, parts[0] == "categoryCountry" else { return nil }
        return String(parts[1])
    }

    static func connect(country: String) {
        guard let url = URL(string: "nordvpn://connect?country=\(country)") else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(url, configuration: config)
    }

    static func openApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// "🇨🇿 Czechia" — flag emoji from the code, name in the system language.
    static func displayName(_ code: String) -> String {
        let flag = code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(0x1F1E6 + $0.value - 0x41) }
            .map(String.init).joined()
        let name = Locale.current.localizedString(forRegionCode: code) ?? code.uppercased()
        return "\(flag) \(name)"
    }
}
