import Foundation

/// The active Focus (Do Not Disturb, Work, Sleep…), if any.
///
/// The public API (INFocusStatusCenter) needs an entitlement a locally signed
/// app can't have, so this reads the files the Focus daemon keeps in the user's
/// Library. Undocumented — verified on macOS 27: an active Focus is an entry in
/// Assertions.json's `storeAssertionRecords`, its name is in ModeConfigurations.json.
enum FocusStatus {
    private static let db = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB")

    /// Name of the active Focus, or nil when none is on (or the files can't be read).
    static func activeName() -> String? {
        guard let assertions = json("Assertions.json"),
              let data = (assertions["data"] as? [[String: Any]])?.first,
              let records = data["storeAssertionRecords"] as? [[String: Any]],
              let mode = records.lazy.compactMap({
                  (($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"]) as? String
              }).first
        else { return nil }

        let root = (json("ModeConfigurations.json")?["data"] as? [[String: Any]])?.first
        let configs = root?["modeConfigurations"] as? [String: Any]
        let config = configs?[mode] as? [String: Any]
        let name = (config?["mode"] as? [String: Any])?["name"] as? String
        return name ?? "Focus"
    }

    private static func json(_ file: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: db.appendingPathComponent(file)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
