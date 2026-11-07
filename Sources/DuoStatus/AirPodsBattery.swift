import Foundation

/// Battery of connected AirPods (or any Bluetooth headset that reports it).
/// There is no public API for this; `system_profiler SPBluetoothDataType`
/// lists it per bud and for the case, in about 0.1 s and without any permission.
struct BudsBattery: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil }

    /// "L 100%, P 100%, case 7%" — whatever the headset reports.
    var label: String {
        [("L", left), ("P", right), ("case", caseLevel)]
            .compactMap { name, level in level.map { "\(name) \($0)%" } }
            .joined(separator: ", ")
    }
}

enum AirPodsBattery {
    /// How long the label stays next to the badge after the headset connects.
    /// Override with `defaults write io.github.zhenweiding-dev.duostatus airPodsBatterySeconds -float 8`
    static var displaySeconds: TimeInterval {
        let v = UserDefaults.standard.double(forKey: "airPodsBatterySeconds")
        return v > 0 ? v : 5
    }

    /// Right after connecting, a headset may not have reported its levels yet.
    private static let retries = 2
    private static let retryDelay: TimeInterval = 2

    /// Reads off the main thread and calls back on it. Prefers the device whose
    /// name matches the current audio output.
    static func read(preferring name: String, attempt: Int = 0,
                     completion: @escaping (BudsBattery?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let found = query(preferring: name)
            DispatchQueue.main.async {
                if found == nil, attempt < retries {
                    DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) {
                        read(preferring: name, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    completion(found)
                }
            }
        }
    }

    private static func query(preferring name: String) -> BudsBattery? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil,
              let data = try? pipe.fileHandleForReading.readToEnd() else { return nil }
        task.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        // device_connected is a list of single-entry dictionaries: [name: properties]
        var candidates: [(String, BudsBattery)] = []
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (deviceName, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    let b = BudsBattery(left: percent(props["device_batteryLevelLeft"]),
                                        right: percent(props["device_batteryLevelRight"]),
                                        caseLevel: percent(props["device_batteryLevelCase"]))
                    if !b.isEmpty { candidates.append((deviceName, b)) }
                }
            }
        }
        return (candidates.first { $0.0 == name } ?? candidates.first)?.1
    }

    /// "100 %" → 100
    private static func percent(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        return Int(s.filter(\.isNumber))
    }
}
