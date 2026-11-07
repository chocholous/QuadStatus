import AppKit

// Enlarged previews of the menu bar badge for the README, drawn by the same code the
// app uses (StatusIcon.image re-renders crisply at any size), so they can't drift
// from what the menu bar shows. Each tile is the badge on a light and a dark menu
// bar strip, side by side.
//
//   build.sh --previews   →   docs/preview/<name>.png

/// How much larger than in the menu bar.
let scale: CGFloat = 6
/// Room around the badge inside each half, in menu bar points.
let pad: CGFloat = 6

func battery(_ level: Double, charging: Bool = false, lowPower: Bool = false) -> BatteryState {
    var b = BatteryState()
    b.present = true
    b.level = level
    b.charging = charging
    b.pluggedIn = charging
    b.lowPowerMode = lowPower
    return b
}

func network(_ kind: NetworkKind = .wifi, bars: Int = 3, online: Bool = true,
             vpn: Bool = false, hotspot: Bool = false) -> NetworkState {
    var n = NetworkState()
    n.kind = kind
    n.bars = bars
    n.online = online
    n.wifiPowerOn = true
    n.vpn = vpn
    n.hotspot = hotspot
    return n
}

let volume = VolumeState(available: true, level: 0.6, muted: false)

func model(battery b: BatteryState = battery(0.72), volume v: VolumeState = volume,
           network n: NetworkState = network(), input: StatusIcon.Input? = nil,
           note: String? = nil, label: String? = nil, pulse: CGFloat = 1) -> StatusIcon.Model {
    var m = StatusIcon.Model(battery: b, volume: v, network: n)
    m.input = input
    m.note = note
    m.label = label
    m.pulse = pulse
    return m
}

let headphones: VolumeState = {
    var v = VolumeState(available: true, level: 0.6, muted: false)
    v.headphones = true
    return v
}()

let previews: [(String, StatusIcon.Model)] = [
    ("overview", model()),
    ("battery-time-left", model(label: "3:12")),
    ("charging", model(battery: battery(0.45, charging: true), label: "1:05")),
    ("low-battery", model(battery: battery(0.12))),
    ("low-power-mode", model(battery: battery(0.38, lowPower: true))),
    ("busy", model(pulse: 0.45)),
    ("volume-muted", model(volume: VolumeState(available: true, level: 0.6, muted: true))),
    ("headphones", model(volume: headphones, note: "L 80% · R 85%")),
    ("wifi-weak", model(network: network(bars: 1))),
    ("no-internet", model(network: network(online: false))),
    ("ethernet", model(network: network(.wired))),
    ("hotspot", model(network: network(hotspot: true))),
    ("vpn", model(network: network(vpn: true))),
    ("vpn-hotspot", model(network: network(vpn: true, hotspot: true))),
    ("vpn-ethernet", model(network: network(.wired, vpn: true))),
    ("keyboard-flag", model(input: .init(letter: "C", language: "cs"))),
    ("keyboard-letter", model(input: .init(letter: "D", language: "de"))),
]

func render(_ m: StatusIcon.Model) -> Data {
    let light = StatusIcon.image(for: m, appearance: NSAppearance(named: .aqua)!)
    let dark = StatusIcon.image(for: m, appearance: NSAppearance(named: .darkAqua)!)
    let half = NSSize(width: light.size.width + 2 * pad, height: light.size.height + 2 * pad)
    let px = NSSize(width: half.width * 2 * scale, height: half.height * scale)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let w = px.width / 2
    for (i, (image, bar)) in [(light, NSColor(white: 0.93, alpha: 1)),
                              (dark, NSColor(white: 0.14, alpha: 1))].enumerated() {
        let x = CGFloat(i) * w
        bar.setFill()
        NSRect(x: x, y: 0, width: w, height: px.height).fill()
        image.draw(in: NSRect(x: x + pad * scale, y: pad * scale,
                              width: image.size.width * scale, height: image.size.height * scale))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

@main
enum RenderPreviews {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, m) in previews {
            try render(m).write(to: out.appendingPathComponent("\(name).png"))
            print("  \(name).png")
        }
    }
}
