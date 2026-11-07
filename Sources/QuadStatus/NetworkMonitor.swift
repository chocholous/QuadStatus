import CoreWLAN
import Network
import SystemConfiguration

enum NetworkKind: Equatable { case wifi, wired, cellular, other, offline }

struct NetworkState: Equatable {
    var kind: NetworkKind = .offline
    var online = false
    var bars = 3                 // 0...3; treated as full when signal can't be read
    var wifiPowerOn = true
    var vpn = false              // traffic goes through a tunnel (utun)
    var tunnelAddress = ""       // the tunnel's own IPv4 address
    var hotspot = false          // Wi-Fi from a phone: the system marks the path expensive
    var interfaceName = ""       // active interface, sampled for throughput
}

/// NWPathMonitor answers "what are we on, and does it work"; CoreWLAN supplies the
/// Wi-Fi signal bars.
///
/// RSSI only, never SSID — the name needs Location permission and the bars don't,
/// and asking for that authorisation to fill one menu row isn't worth it.
final class NetworkMonitor {
    private(set) var state = NetworkState()
    var onChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.github.chocholous.quadstatus.network")
    private var path: NWPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.path = path
                self?.refresh()
            }
        }
        monitor.start(queue: queue)
        refresh()
    }

    func refresh() {
        let new = read()
        guard new != state else { return }
        state = new
        onChange?()
    }

    private func read() -> NetworkState {
        var s = NetworkState()

        guard let path else { return s }
        s.online = (path.status == .satisfied)
        s.interfaceName = path.availableInterfaces.first?.name ?? ""

        if path.usesInterfaceType(.wifi) {
            s.kind = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            s.kind = .wired
        } else if path.usesInterfaceType(.cellular) {
            s.kind = .cellular
        } else if s.online {
            s.kind = .other
        } else {
            s.kind = .offline
        }

        // A VPN tunnel (utun) reports as .other even when it rides on Wi-Fi. If the
        // radio is on and associated (rssiValue() is 0 when it isn't), show Wi-Fi.
        if s.kind == .other, let iface = CWWiFiClient.shared().interface(),
           iface.powerOn(), iface.rssiValue() != 0 {
            s.kind = .wifi
        }
        if s.interfaceName.hasPrefix("utun") {
            s.vpn = true
            s.tunnelAddress = Self.ipv4(of: s.interfaceName) ?? ""
        }
        s.hotspot = s.kind == .wifi
            && (path.isExpensive || Self.wifiRouter() == Self.iPhoneHotspotRouter)

        // Read the radio when on Wi-Fi, and also when offline on a machine that has
        // a Wi-Fi interface — that's what separates "Wi-Fi is off" from "connected
        // but no internet".
        if let iface = CWWiFiClient.shared().interface(), s.kind == .wifi || !s.online {
            s.wifiPowerOn = iface.powerOn()
            if !s.wifiPowerOn { s.kind = .offline }

            // rssiValue() returns 0 when it can't be read; treat that as full bars.
            let raw = iface.rssiValue()
            s.bars = raw == 0 ? 3 : Self.bars(forRSSI: raw)
        }

        if !s.online { s.bars = 0 }
        return s
    }

    /// iPhone Personal Hotspot always hands out 172.20.10.0/28 with itself as the
    /// router. Catches it even when the network isn't flagged as expensive
    /// (isExpensive alone also covers Android hotspots and metered networks).
    private static let iPhoneHotspotRouter = "172.20.10.1"

    /// The IPv4 router of the Wi-Fi interface itself — not the default route,
    /// which points into the tunnel while a VPN is up.
    private static func wifiRouter() -> String? {
        guard let bsd = CWWiFiClient.shared().interface()?.interfaceName,
              let store = SCDynamicStoreCreate(nil, "QuadStatus" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString)
                as? [CFString] else { return nil }
        for key in keys {
            guard let v = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  v["InterfaceName"] as? String == bsd else { continue }
            return v["Router"] as? String
        }
        return nil
    }

    private static func ipv4(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard String(cString: a.ifa_name) == interface,
                  let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
    }

    private static func bars(forRSSI rssi: Int) -> Int {
        if rssi >= -60 { return 3 }
        if rssi >= -70 { return 2 }
        if rssi >= -80 { return 1 }
        return 0
    }
}
