import AppKit
import CoreAudio
import CoreWLAN

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let battery = BatteryMonitor()
    private let volume = VolumeMonitor()
    private let network = NetworkMonitor()
    private let throughput = ThroughputMeter()
    private let keyboard = InputSourceMonitor()
    private let wifi = WiFiAccess()

    private var pollTimer: Timer?
    private var hoverTip: HoverTip?

    /// AirPods battery shown next to the badge for a few seconds after connecting
    private var budsNote: String?
    private var budsNoteTimer: Timer?
    private var hadHeadphones = false
    private var budsBattery: BudsBattery?

    /// CPU load from which the hover tip lists it
    private static let tipCPULoad = 0.70

    /// Under heavy CPU load or thermal pressure the battery arc breathes gently.
    private let stress = StressMonitor()
    private var pulseTimer: Timer?
    private var pulseStart = Date()
    private static let pulsePeriod: TimeInterval = 1.6
    private static let pulseFPS: Double = 12       // the animation itself must stay cheap
    private static let pulseFloor: CGFloat = 0.45  // dimmest point of a breath
    private var appearanceObservation: NSKeyValueObservation?
    private var renderedModel: StatusIcon.Model?
    /// Pointer over the badge: the arc shows percent instead of time
    private var hovering = false
    private var ping: PingResult?
    private var pinging = false

    /// One closure per row, each writes its own title with the latest value.
    private var liveRows: [() -> Void] = []
    private var liveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginAgent.migrate()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        if let button = statusItem.button {
            hoverTip = HoverTip(button: button) { [weak self] in self?.tipLines() ?? [] }
            hoverTip?.willShow = { [weak self] in self?.refreshBudsForTip() }
            hoverTip?.onHover = { [weak self] in
                self?.hovering = $0
                self?.render()
            }
        }

        battery.onChange = { [weak self] in self?.render() }
        volume.onChange = { [weak self] in
            self?.headphonesChanged()
            self?.render()
        }
        network.onChange = { [weak self] in self?.render() }
        keyboard.onChange = { [weak self] in self?.render() }
        stress.onChange = { [weak self] in self?.updatePulse() }

        // The icon isn't a template image, so it has to follow the menu bar
        // appearance itself.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.render(force: true)
        }

        // Safety net: a few devices never post change notifications, and Wi-Fi
        // signal strength has no push event at all. Throughput rides along, so
        // what it reports is a 5-second average.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }

        render(force: true)
    }

    private func refreshAll() {
        battery.refresh()
        volume.refresh()
        network.refresh()
        keyboard.refresh()
        stress.refresh()
        throughput.sample(interface: network.state.interfaceName)
    }

    private var pulseLevel: CGFloat {
        guard pulseTimer != nil else { return 1 }
        let t = Date().timeIntervalSince(pulseStart) / Self.pulsePeriod
        let wave = (1 + cos(2 * .pi * t)) / 2              // 1 → 0 → 1 per period
        return Self.pulseFloor + (1 - Self.pulseFloor) * CGFloat(wave)
    }

    private func updatePulse() {
        if stress.stressed, pulseTimer == nil {
            pulseStart = Date()
            let timer = Timer(timeInterval: 1 / Self.pulseFPS, repeats: true) { [weak self] _ in
                self?.render()
            }
            RunLoop.main.add(timer, forMode: .common)
            pulseTimer = timer
        } else if !stress.stressed, let timer = pulseTimer {
            timer.invalidate()
            pulseTimer = nil
            render(force: true)
        }
    }

    /// On the switch to headphones, read their battery and show it briefly.
    private func headphonesChanged() {
        let now = volume.state.headphones
        defer { hadHeadphones = now }
        guard now, !hadHeadphones else { return }
        AirPodsBattery.read(preferring: volume.state.outputName) { [weak self] battery in
            guard let self, let battery, self.volume.state.headphones else { return }
            self.budsBattery = battery
            self.budsNote = battery.label
            self.render(force: true)
            self.budsNoteTimer?.invalidate()
            self.budsNoteTimer = Timer.scheduledTimer(withTimeInterval: AirPodsBattery.displaySeconds,
                                                      repeats: false) { [weak self] _ in
                self?.budsNote = nil
                self?.render(force: true)
            }
        }
    }

    /// Measured only while the menu is open. Skipped if one is still in flight
    /// so requests can't pile up.
    private func measurePing() {
        guard !pinging, let gateway = Pinger.defaultGateway() else { return }
        pinging = true
        Pinger.measure(host: gateway, count: 3) { [weak self] result in
            self?.pinging = false
            self?.ping = result
        }
    }

    // MARK: - Live refresh while the menu is open

    /// An open menu puts the run loop in event-tracking mode, where timers
    /// scheduled in the default mode never fire — hence the explicit `.common`.
    /// Stops on close: nobody is looking the rest of the time.
    func menuWillOpen(_ menu: NSMenu) {
        hoverTip?.hide()
        tickLive()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tickLive() }
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        liveTimer?.invalidate()
        liveTimer = nil
        liveRows.removeAll()
    }

    private func tickLive() {
        refreshAll()
        measurePing()
        for update in liveRows { update() }
    }

    // MARK: - Status icon

    private func render(force: Bool = false) {
        guard let button = statusItem.button else { return }
        let model = StatusIcon.Model(battery: battery.state,
                                     volume: volume.state,
                                     network: network.state,
                                     input: keyboard.shown.map { .init(letter: $0.letter, language: $0.language) },
                                     note: budsNote,
                                     label: arcLabel(battery.state),
                                     pulse: pulseLevel)
        guard force || model != renderedModel else { return }
        renderedModel = model

        let image = StatusIcon.image(for: model, appearance: button.effectiveAppearance)
        button.image = image
        statusItem.length = image.size.width
    }

    /// The number in the top of the battery arc: time left or to full as h:mm,
    /// the percentage while hovered, while macOS is still estimating, or on power
    /// but not charging. Past 9:59 it's whole hours, to stay inside the ring's cut.
    private func arcLabel(_ b: BatteryState) -> String? {
        guard b.present else { return nil }
        let m = b.minutesRemaining
        guard !hovering, m > 0, b.charging || !b.pluggedIn else { return "\(Int(round(b.level * 100)))" }
        return m >= 600 ? "\(m / 60)h" : String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Hover text, one fact per line: network name, VPN country while connected,
    /// battery, AirPods (each bud and the case, when known), CPU when it's busy.
    private func tipLines() -> [HoverTip.Line] {
        let n = network.state, s = L.strings
        var lines: [HoverTip.Line] = []
        switch n.kind {
        case .wifi where n.hotspot: lines.append(.init(text: s.hotspot))
        case .wifi:                 lines.append(.init(text: CWWiFiClient.shared().interface()?.ssid() ?? "Wi-Fi"))
        case .wired:                lines.append(.init(text: s.ethernet))
        case .offline:              lines.append(.init(text: n.wifiPowerOn ? s.notConnected : s.wifiOff))
        case .cellular, .other:     break
        }
        if n.vpn {
            lines.append(.init(text: "VPN " + (NordVPN.lastCountry.map(NordVPN.displayName) ?? s.connected)))
        }
        let b = battery.state
        if b.present {
            // With the system battery icon hidden, time left / to full is the thing
            // the percentage alone doesn't say. -1 while macOS is still estimating.
            var text = "\(Int(round(b.level * 100))) %"
            let m = b.minutesRemaining
            if m > 0, b.charging { text += " · " + s.timeToFull(m / 60, m % 60) }
            else if m > 0, !b.pluggedIn { text += " · " + s.timeLeft(m / 60, m % 60) }
            lines.append(.init(symbol: "laptopcomputer", text: text))
        }
        if volume.state.headphones, let buds = budsBattery {
            if let l = buds.left      { lines.append(.init(symbol: "airpodpro.left", text: "\(l) %")) }
            if let r = buds.right     { lines.append(.init(symbol: "airpodpro.right", text: "\(r) %")) }
            if let c = buds.caseLevel { lines.append(.init(symbol: "airpodspro.chargingcase.wireless", text: "\(c) %")) }
        }
        // Its menu bar icon is hidden too, so say when a Focus is silencing things
        if let focus = FocusStatus.activeName() {
            lines.append(.init(symbol: "moon.fill", text: focus))
        }
        if stress.load >= Self.tipCPULoad {
            lines.append(.init(symbol: "cpu", text: "\(Int(round(stress.load * 100))) %"))
        }
        return lines
    }

    /// Fresh AirPods levels for the hover tip; it fills in when they arrive.
    private func refreshBudsForTip() {
        guard volume.state.headphones else { budsBattery = nil; return }
        AirPodsBattery.read(preferring: volume.state.outputName) { [weak self] battery in
            guard let self, let battery else { return }
            self.budsBattery = battery
            self.hoverTip?.refresh()
        }
    }

    // MARK: - Menu

    /// Pin the width to the longest text each row can produce, otherwise the
    /// whole panel resizes every time a number gains or loses a digit.
    private static func menuWidth(for strings: Strings) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let widest = strings.widthSamples
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 250
        return ceil(widest) + 64          // icon + insets + submenu arrow
    }

    /// Width left for a device name once the prefix and insets are accounted for.
    private static func deviceNameWidth(for strings: Strings) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let prefix = ("\(strings.output) " as NSString).size(withAttributes: [.font: font]).width
        return menuWidth(for: strings) - 64 - prefix
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshAll()
        menu.removeAllItems()
        liveRows.removeAll()

        let s = L.strings
        menu.minimumWidth = Self.menuWidth(for: s)

        menu.addItem(.sectionHeader(title: s.battery))
        live(menu, symbol: { [weak self] in self?.batterySymbol() ?? "battery.50percent" }) {
            [weak self] in self?.batteryLine() ?? ""
        }
        live(menu, symbol: { [weak self] in
            self?.battery.state.pluggedIn == true ? "powerplug.fill" : "timer"
        }) { [weak self] in self?.powerLine() ?? "" }

        menu.addItem(.sectionHeader(title: s.network))
        live(menu, symbol: { [weak self] in self?.networkSymbol() ?? "wifi" }) {
            [weak self] in self?.networkLine() ?? ""
        }
        live(menu, symbol: { "arrow.up.arrow.down" }) { [weak self] in self?.linkLine() ?? "" }
        wifi.requestIfNeeded()
        if !wifi.allowed {
            let allow = NSMenuItem(title: s.wifiAllowLocation,
                                   action: #selector(WiFiAccess.openLocationSettings), keyEquivalent: "")
            allow.target = wifi
            Self.apply(symbol: "location", to: allow)
            menu.addItem(allow)
        }
        let settings = NSMenuItem(title: s.wifiSettings,
                                  action: #selector(WiFiAccess.openWiFiSettings), keyEquivalent: "")
        settings.target = wifi
        Self.apply(symbol: "gearshape", to: settings)
        menu.addItem(settings)

        if NordVPN.installed {
            menu.addItem(.sectionHeader(title: "VPN"))
            live(menu, symbol: { [weak self] in
                self?.network.state.vpn == true ? "lock.shield.fill" : "lock.open"
            }) { [weak self] in self?.vpnLine() ?? "" }
            menu.addItem(vpnCountryItem())
            let open = NSMenuItem(title: s.openNordVPN, action: #selector(openNordVPN), keyEquivalent: "")
            open.target = self
            Self.apply(symbol: "arrow.up.forward.app", to: open)
            menu.addItem(open)
        }

        menu.addItem(.sectionHeader(title: s.sound))
        live(menu, symbol: { [weak self] in
            self?.volume.state.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }) { [weak self] in self?.soundLine() ?? "" }
        menu.addItem(deviceItem(title: s.output, symbol: "hifispeaker.fill", scope: .output))
        menu.addItem(deviceItem(title: s.input, symbol: "mic.fill", scope: .input))

        menu.addItem(.sectionHeader(title: s.keyboard))
        menu.addItem(keyboardItem())

        menu.addItem(.separator())
        menu.addItem(languageItem())

        let login = NSMenuItem(title: s.openAtLogin, action: #selector(toggleLoginItem), keyEquivalent: "")
        login.state = LoginAgent.isEnabled ? .on : .off
        login.target = self
        menu.addItem(login)

        let quit = NSMenuItem(title: s.quit,
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// Adds a read-only row with an SF Symbol and registers how to refresh it.
    private func live(_ menu: NSMenu, symbol: @escaping () -> String,
                      _ text: @escaping () -> String) {
        let item = NSMenuItem(title: text(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        Self.apply(symbol: symbol(), to: item)
        menu.addItem(item)
        liveRows.append { [weak item] in
            guard let item else { return }
            item.title = text()
            Self.apply(symbol: symbol(), to: item)
        }
    }

    /// From macOS 27 on, AppKit hides menu item images unless told otherwise.
    private static func apply(symbol: String, to item: NSMenuItem) {
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
    }

    private func batterySymbol() -> String {
        let s = battery.state
        if s.charging { return "battery.100percent.bolt" }
        switch s.level {
        case ..<0.15: return "battery.0percent"
        case ..<0.40: return "battery.25percent"
        case ..<0.65: return "battery.50percent"
        case ..<0.90: return "battery.75percent"
        default:      return "battery.100percent"
        }
    }

    private func networkSymbol() -> String {
        let s = network.state
        switch s.kind {
        case .wired, .cellular, .other: return s.online ? "globe" : "globe.badge.chevron.backward"
        case .wifi where s.hotspot: return "personalhotspot"
        case .wifi:    return s.online ? "wifi" : "wifi.exclamationmark"
        case .offline: return "wifi.slash"
        }
    }

    private func languageItem() -> NSMenuItem {
        let submenu = NSMenu()
        for language in AppLanguage.allCases {
            let entry = NSMenuItem(title: language.menuTitle,
                                   action: #selector(selectLanguage(_:)), keyEquivalent: "")
            entry.state = L.language == language ? .on : .off
            entry.representedObject = language.rawValue
            entry.target = self
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: L.strings.language, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The active layout, with a submenu to switch — stands in for the system
    /// input menu once that is hidden.
    private func keyboardItem() -> NSMenuItem {
        let submenu = NSMenu()
        let currentID = keyboard.current?.id
        for source in keyboard.selectable {
            let entry = NSMenuItem(title: source.name,
                                   action: #selector(selectInputSource(_:)), keyEquivalent: "")
            entry.state = source.id == currentID ? .on : .off
            entry.representedObject = source.id
            entry.target = self
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: keyboard.current?.name ?? "—", action: nil, keyEquivalent: "")
        item.submenu = submenu
        Self.apply(symbol: "keyboard", to: item)
        return item
    }

    /// Countries to connect to, the current one ticked. NordVPN takes a while to
    /// switch, so the tick follows on the next menu open.
    private func vpnCountryItem() -> NSMenuItem {
        let submenu = NSMenu()
        let current = network.state.vpn ? NordVPN.lastCountry : nil
        for code in NordVPN.countries {
            let entry = NSMenuItem(title: NordVPN.displayName(code),
                                   action: #selector(connectVPN(_:)), keyEquivalent: "")
            entry.state = code == current ? .on : .off
            entry.representedObject = code
            entry.target = self
            submenu.addItem(entry)
        }
        let item = NSMenuItem(title: L.strings.connectTo, action: nil, keyEquivalent: "")
        item.submenu = submenu
        Self.apply(symbol: "globe.europe.africa", to: item)
        return item
    }

    private enum DeviceScope { case output, input }

    private func deviceItem(title: String, symbol: String, scope: DeviceScope) -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu()
        item.submenu = submenu
        Self.apply(symbol: symbol, to: item)

        let refresh: () -> Void = { [weak self, weak item, weak submenu] in
            guard let self, let item, let submenu else { return }
            let state = self.volume.state
            let name = scope == .output ? state.outputName : state.inputName
            let current = scope == .output ? self.volume.currentOutput : self.volume.currentInput

            let shown = Self.fit(name.isEmpty ? "—" : name,
                                 within: Self.deviceNameWidth(for: L.strings))
            // Same grey as the other status rows. `isEnabled = false` would look
            // right but makes the submenu unreachable, hence the attributed title.
            item.attributedTitle = NSAttributedString(string: "\(title) \(shown)", attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])

            let devices = scope == .output ? self.volume.outputDevices : self.volume.inputDevices
            if submenu.items.count != devices.count {
                submenu.removeAllItems()
                for device in devices {
                    let entry = NSMenuItem(
                        title: device.name,
                        action: scope == .output ? #selector(self.selectOutput(_:))
                                                 : #selector(self.selectInput(_:)),
                        keyEquivalent: "")
                    entry.representedObject = device.id
                    entry.target = self
                    submenu.addItem(entry)
                }
            }
            for (entry, device) in zip(submenu.items, devices) {
                entry.state = device.id == current ? .on : .off
            }
        }
        refresh()
        liveRows.append(refresh)
        return item
    }

    /// Truncates from the tail with an ellipsis. Device names vary wildly in
    /// length and a long one would widen the whole panel.
    private static func fit(_ text: String, within maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        guard (text as NSString).size(withAttributes: attrs).width > maxWidth else { return text }
        var cut = text
        while !cut.isEmpty,
              ((cut + "…") as NSString).size(withAttributes: attrs).width > maxWidth {
            cut.removeLast()
        }
        return cut + "…"
    }

    // MARK: - Row text

    private func batteryLine() -> String {
        let b = battery.state, s = L.strings
        guard b.present else { return "" }
        var parts = ["\(Int(round(b.level * 100)))%"]
        if let health = b.healthPercent { parts.append(s.health(health)) }
        if b.cycleCount > 0 { parts.append(s.cycles(b.cycleCount)) }
        if b.lowPowerMode { parts.append(s.lowPowerMode) }
        return parts.joined(separator: " · ")
    }

    private func powerLine() -> String {
        let b = battery.state, s = L.strings
        guard b.present else { return "" }
        if b.pluggedIn {
            var parts: [String] = []
            if b.adapterWatts > 0 { parts.append("\(b.adapterWatts)W") }
            if b.adapterVolts > 0 {
                parts.append(String(format: "%.0fV %.2fA", b.adapterVolts, b.adapterAmps))
            }
            if b.charging, b.powerWatts > 0.1 { parts.append(s.charging(b.powerWatts)) }
            return parts.isEmpty ? s.powerConnected : parts.joined(separator: " · ")
        }
        guard b.minutesRemaining > 0 else { return s.onBatteryEstimating }
        return s.onBattery(b.minutesRemaining / 60, b.minutesRemaining % 60)
    }

    private func vpnLine() -> String {
        let n = network.state, s = L.strings
        guard n.vpn else { return s.notConnected }
        var parts = [s.connected]
        if let country = NordVPN.lastCountry { parts.append(NordVPN.displayName(country)) }
        if !n.tunnelAddress.isEmpty { parts.append(n.tunnelAddress) }
        return parts.joined(separator: " · ")
    }

    private func networkLine() -> String {
        let n = network.state, s = L.strings
        let state = n.online ? s.connected : s.noInternet
        switch n.kind {
        case .offline:  return n.wifiPowerOn ? s.notConnected : s.wifiOff
        case .wired:    return "\(s.ethernet) · \(state)"
        case .cellular: return s.cellular
        case .other:    return state
        case .wifi:
            // The SSID needs Location access; without it, fall back to "Wi-Fi"
            let name = n.hotspot ? s.hotspot : (CWWiFiClient.shared().interface()?.ssid() ?? "Wi-Fi")
            return "\(name) · \(state)"
        }
    }

    /// Rates and latency on one line. The two directions share a unit and the
    /// latency/loss labels are dropped — this is the widest row, and spelling
    /// them out costs 55pt. The ⇅ symbol already says it is about traffic.
    private func linkLine() -> String {
        let r = throughput.rate, s = L.strings
        let useMB = max(r.down, r.up) >= 1_048_576
        let scale = useMB ? 1_048_576.0 : 1024.0
        var line = "↓\(Self.compact(r.down / scale)) ↑\(Self.compact(r.up / scale)) "
            + (useMB ? "MB/s" : "KB/s")
        guard let p = ping else { return line + s.measuring }
        line += p.lossPercent == 100
            ? s.noResponse
            : " · \(Self.compact(p.milliseconds))ms · \(p.lossPercent)%"
        return line
    }

    /// Drop the decimal past three digits — this row sets the panel width, and
    /// "1250.0" wastes 20pt over "1250".
    private static func compact(_ value: Double) -> String {
        String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }

    private func soundLine() -> String {
        let v = volume.state, s = L.strings
        guard v.available else { return s.volumeUnavailable }
        return v.muted ? s.muted : "\(Int(round(v.level * 100)))%"
    }

    // MARK: - Actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        L.language = language
        render(force: true)          // refreshes the tooltip; the menu rebuilds on open
    }

    @objc private func selectInputSource(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { keyboard.select(id: id) }
    }

    @objc private func connectVPN(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { NordVPN.connect(country: code) }
    }

    @objc private func openNordVPN() { NordVPN.openApp() }

    @objc private func selectOutput(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? AudioDeviceID { volume.selectOutput(id) }
    }

    @objc private func selectInput(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? AudioDeviceID { volume.selectInput(id) }
    }

    @objc private func toggleLoginItem() {
        do {
            if LoginAgent.isEnabled {
                try LoginAgent.disable()
            } else {
                try LoginAgent.enable()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L.strings.loginItemFailed
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
