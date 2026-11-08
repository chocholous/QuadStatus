import AppKit

// The README images, drawn by the same code the app uses (StatusIcon.image
// re-renders crisply at any size), so they can't drift from what the menu bar
// shows. Every image comes in a light and a dark variant; the README picks one
// with <picture> and prefers-color-scheme.
//
//   build.sh --previews   →   docs/preview/<name>-light.png, <name>-dark.png
//
// Sizes are in points of the README page (CSS pixels); every image is written
// at `pixelScale` times that, so it stays sharp on Retina screens. The README
// sets each <img> width to the point width printed here.

/// Bitmap pixels per README point.
let pixelScale: CGFloat = 2

// MARK: - Themes

/// Colours that frame the badge. The badge itself, the SF Symbols and the clock
/// take the real system colours of the matching NSAppearance.
struct Theme {
    let name: String
    let appearance: NSAppearance
    /// Desktop picture behind the menu bar: top-left to bottom-right
    let wallpaper: [NSColor]
    /// The translucent band of the menu bar over the wallpaper
    let bar: NSColor
    /// Small cards in the gallery
    let tile: [NSColor]
    let tileBorder: NSColor
    /// Captions printed on GitHub's own page background (primer fg.default / fg.muted)
    let text: NSColor
    let secondary: NSColor
    /// The hover tip under the badge
    let tip: NSColor
    let tipBorder: NSColor
}

func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

let themes = [
    Theme(name: "light", appearance: NSAppearance(named: .aqua)!,
          wallpaper: [hex(0xB9D4F5), hex(0xD9DEF7), hex(0xF6DCCB)],
          bar: NSColor(white: 1, alpha: 0.38),
          tile: [hex(0xF7F7F9), hex(0xE9EAEF)], tileBorder: NSColor(white: 0, alpha: 0.08),
          text: hex(0x1F2328), secondary: hex(0x59636E),
          tip: NSColor(white: 0.97, alpha: 0.96), tipBorder: NSColor(white: 0, alpha: 0.12)),
    Theme(name: "dark", appearance: NSAppearance(named: .darkAqua)!,
          wallpaper: [hex(0x14213D), hex(0x2B2350), hex(0x4A2740)],
          bar: NSColor(white: 0, alpha: 0.22),
          tile: [hex(0x2A2B30), hex(0x1E1F23)], tileBorder: NSColor(white: 1, alpha: 0.09),
          text: hex(0xF0F6FC), secondary: hex(0x9198A1),
          tip: NSColor(white: 0.17, alpha: 0.96), tipBorder: NSColor(white: 1, alpha: 0.14)),
]

// MARK: - Badge states

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

let headphones: VolumeState = {
    var v = VolumeState(available: true, level: 0.6, muted: false)
    v.headphones = true
    return v
}()

/// On a MacBook the arc always carries a number: time left (or to full), or the
/// percentage while hovered or estimating. These previews use time left.
let timeLeft = "3:12"

func model(battery b: BatteryState = battery(0.72), volume v: VolumeState = volume,
           network n: NetworkState = network(), input: StatusIcon.Input? = nil,
           label: String? = timeLeft, pulse: CGFloat = 1) -> StatusIcon.Model {
    var m = StatusIcon.Model(battery: b, volume: v, network: n)
    m.input = input
    m.label = label
    m.pulse = pulse
    return m
}

// MARK: - Drawing helpers

/// Renders `draw` into a PNG of `size` points at `pixelScale`, y pointing up.
func png(_ size: NSSize, _ theme: Theme, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * pixelScale),
        pixelsHigh: Int(size.height * pixelScale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    theme.appearance.performAsCurrentDrawingAppearance { draw() }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func badge(_ m: StatusIcon.Model, _ theme: Theme) -> NSImage {
    StatusIcon.image(for: m, appearance: theme.appearance)
}

/// The badge `zoom` times its menu bar size, its left edge at `x`, centred on `midY`.
func drawBadge(_ m: StatusIcon.Model, _ theme: Theme, x: CGFloat, midY: CGFloat, zoom: CGFloat) {
    let image = badge(m, theme)
    image.draw(in: NSRect(x: x, y: midY - image.size.height * zoom / 2,
                          width: image.size.width * zoom, height: image.size.height * zoom))
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular,
            color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
}

func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
}

/// A gradient drawn one pixel-wide band at a time. NSGradient dithers, and the
/// noise roughly triples the PNG; plain bands are identical along each row (or
/// column), which PNG's filters squeeze down to almost nothing.
func gradient(_ colors: [NSColor], in path: NSBezierPath, vertical: Bool) {
    let g = NSGradient(colors: colors)!
    let r = path.bounds
    let length = vertical ? r.height : r.width
    let steps = Int(ceil(length * pixelScale))
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(max(steps - 1, 1))
        // Top to bottom, or left to right
        g.interpolatedColor(atLocation: t).setFill()
        let step = 1 / pixelScale
        (vertical ? NSRect(x: r.minX, y: r.maxY - CGFloat(i + 1) * step, width: r.width, height: step)
                  : NSRect(x: r.minX + CGFloat(i) * step, y: r.minY, width: step, height: r.height)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Menu bar

/// Measured on a 14" MacBook with a notch (macOS 27): the menu bar is 34pt
/// tall and set in the 13pt system font. The badge is 28pt, so it needs the
/// taller bar of a notched MacBook to look right.
enum Bar {
    static let height: CGFloat = 34
    static let font = NSFont.menuBarFont(ofSize: 0)
    static let symbolSize: CGFloat = 14.5
    /// Between the contents of neighbouring items
    static let spacing: CGFloat = 14
    static let rightInset: CGFloat = 13
    static let clock = "Sun Nov 8  9:41 AM"
}

enum BarItem {
    case symbol(String)
    case badge(StatusIcon.Model)
    case inputMenu(String)
    case clock
}

/// The bar's contents, right-aligned to `right` in a bar `zoom` times real size.
/// Returns each item's frame, left to right, so callers can point at one.
@discardableResult
func drawBarItems(_ items: [BarItem], _ theme: Theme, right: CGFloat, y: CGFloat,
                  zoom: CGFloat) -> [NSRect] {
    let ink = NSColor.labelColor
    let midY = y + Bar.height * zoom / 2
    var x = right - Bar.rightInset * zoom
    var frames: [NSRect] = []
    for item in items.reversed() {
        let width: CGFloat
        switch item {
        case .symbol(let name):
            let s = symbol(name, size: Bar.symbolSize * zoom, color: ink)
            width = s.size.width
            s.draw(in: NSRect(x: x - width, y: midY - s.size.height / 2,
                              width: width, height: s.size.height))
        case .badge(let m):
            let image = badge(m, theme)
            width = image.size.width * zoom
            drawBadge(m, theme, x: x - width, midY: midY, zoom: zoom)
        case .inputMenu(let letters):
            // The system input menu: the layout's letters in a rounded box
            let font = NSFont.systemFont(ofSize: 9.5 * zoom, weight: .semibold)
            let label = text(letters, font, ink)
            let box = NSSize(width: label.size().width + 7 * zoom, height: 15 * zoom)
            width = box.width
            let rect = NSRect(x: x - width, y: midY - box.height / 2, width: box.width, height: box.height)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6 * zoom, dy: 0.6 * zoom),
                                    xRadius: 3.5 * zoom, yRadius: 3.5 * zoom)
            path.lineWidth = 1.2 * zoom
            ink.setStroke()
            path.stroke()
            label.draw(at: NSPoint(x: rect.midX - label.size().width / 2,
                                   y: rect.midY - label.size().height / 2 + 0.2 * zoom))
        case .clock:
            let font = NSFont.menuBarFont(ofSize: Bar.font.pointSize * zoom)
            let label = text(Bar.clock, font, ink)
            width = label.size().width
            label.draw(at: NSPoint(x: x - width, y: midY - label.size().height / 2))
        }
        frames.insert(NSRect(x: x - width, y: y, width: width, height: Bar.height * zoom), at: 0)
        x -= width + Bar.spacing * zoom
    }
    return frames
}

/// Third-party utilities on the left, then the system's Spotlight, Control
/// Center and clock: a typical right end of the menu bar.
let leftApps: [BarItem] = [.symbol("doc.on.clipboard"), .symbol("cup.and.saucer")]
let systemTail: [BarItem] = [.symbol("magnifyingglass"), .symbol("switch.2"), .clock]
/// What QuadStatus stands in for: the input menu, Sound, Battery and Wi-Fi
let replaced: [BarItem] = [.inputMenu("ABC"), .symbol("speaker.wave.2.fill"),
                           .symbol("battery.75percent"), .symbol("wifi")]

// MARK: - Hero: the right end of the menu bar, badge hovered

func hero(_ theme: Theme) -> (NSSize, Data) {
    let size = NSSize(width: 840, height: 172)
    let zoom: CGFloat = 2
    let data = png(size, theme) {
        let card = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 18, yRadius: 18)
        card.addClip()
        wallpaper(theme, in: NSRect(origin: .zero, size: size))

        let barY = size.height - Bar.height * zoom
        theme.bar.setFill()
        NSRect(x: 0, y: barY, width: size.width, height: Bar.height * zoom).fill()

        // Hovered: the arc shows the percentage, and the tip lists the details
        let hovered = model(label: "72")
        let frames = drawBarItems(leftApps + [.badge(hovered)] + systemTail, theme,
                                  right: size.width, y: barY, zoom: zoom)
        drawTip(lines: [(nil, "Home"), ("laptopcomputer", "72 % · 3:12 left")],
                under: frames[leftApps.count], theme: theme, zoom: zoom)
    }
    return (size, data)
}

/// Left to right only, so it compresses well (see `gradient`).
func wallpaper(_ theme: Theme, in rect: NSRect) {
    gradient(theme.wallpaper, in: NSBezierPath(rect: rect), vertical: false)
}

/// The app's hover tip (HoverTip.swift): tooltip font, a symbol per line.
func drawTip(lines: [(String?, String)], under item: NSRect, theme: Theme, zoom: CGFloat) {
    let font = NSFont.toolTipsFont(ofSize: NSFont.toolTipsFont(ofSize: 0).pointSize * zoom)
    let ink = NSColor.labelColor
    let rows: [NSAttributedString] = lines.map { name, string in
        let row = NSMutableAttributedString()
        if let name {
            let s = symbol(name, size: font.pointSize, color: ink)
            let attachment = NSTextAttachment()
            attachment.image = s
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - s.size.height) / 2,
                                       width: s.size.width, height: s.size.height)
            row.append(NSAttributedString(attachment: attachment))
            row.append(text("  ", font, ink))
        }
        row.append(text(string, font, ink))
        return row
    }
    let lineHeight = ceil(font.ascender - font.descender + font.leading) + 1 * zoom
    let pad = NSSize(width: 8 * zoom, height: 4 * zoom)
    let width = ceil(rows.map { $0.size().width }.max()!) + 2 * pad.width
    let height = lineHeight * CGFloat(rows.count) + 2 * pad.height
    let rect = NSRect(x: item.midX - width / 2, y: item.minY - 4 * zoom - height,
                      width: width, height: height)

    let shape = NSBezierPath(roundedRect: rect, xRadius: 5 * zoom, yRadius: 5 * zoom)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.25)
    shadow.shadowBlurRadius = 10 * zoom
    shadow.shadowOffset = NSSize(width: 0, height: -2 * zoom)
    shadow.set()
    theme.tip.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.lineWidth = 1
    theme.tipBorder.setStroke()
    shape.stroke()

    for (i, row) in rows.enumerated() {
        row.draw(at: NSPoint(x: rect.minX + pad.width,
                             y: rect.maxY - pad.height - lineHeight * CGFloat(i + 1) + 1 * zoom))
    }
}

// MARK: - Before and after

/// Two crops of the same menu bar, right-aligned so the clock lines up: four
/// system icons, then the badge in their place.
func beforeAfter(_ theme: Theme) -> (NSSize, Data) {
    let zoom: CGFloat = 2
    let barH = Bar.height * zoom
    let gap: CGFloat = 14
    let labelWidth: CGFloat = 86
    let size = NSSize(width: 840, height: barH * 2 + gap)
    let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
    let data = png(size, theme) {
        for (row, (label, items)) in [("Before", leftApps + replaced + systemTail),
                                      ("After", leftApps + [.badge(model())] + systemTail)].enumerated() {
            let y = size.height - CGFloat(row + 1) * barH - CGFloat(row) * gap
            let caption = text(label, font, row == 0 ? theme.secondary : theme.text)
            caption.draw(at: NSPoint(x: 0, y: y + (barH - caption.size().height) / 2))

            let strip = NSRect(x: labelWidth, y: y, width: size.width - labelWidth, height: barH)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: strip, xRadius: 14, yRadius: 14).addClip()
            wallpaper(theme, in: NSRect(x: 0, y: 0, width: size.width, height: size.height))
            theme.bar.setFill()
            strip.fill()
            drawBarItems(items, theme, right: size.width, y: y, zoom: zoom)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    return (size, data)
}

// MARK: - Anatomy: the badge enlarged, each part labelled

func anatomy(_ theme: Theme) -> (NSSize, Data) {
    let size = NSSize(width: 840, height: 300)
    let zoom: CGFloat = 5.5
    // A letter rather than a flag: it sits beside the ring, so every part can be pointed at
    let m = model(input: .init(letter: "D", language: "de"))
    let image = badge(m, theme)
    let badgeSize = NSSize(width: image.size.width * zoom, height: image.size.height * zoom)
    let origin = NSPoint(x: (size.width - badgeSize.width) / 2, y: (size.height - badgeSize.height) / 2)
    /// A point on the badge, in its own menu bar coordinates, mapped onto the canvas
    func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: origin.x + x * zoom, y: origin.y + y * zoom)
    }
    let M = StatusIcon.M.self

    let data = png(size, theme) {
        let card = NSBezierPath(roundedRect: NSRect(x: origin.x - 36, y: 14,
                                                    width: badgeSize.width + 72, height: size.height - 28),
                                xRadius: 28, yRadius: 28)
        gradient(theme.tile, in: card, vertical: true)
        card.lineWidth = 1
        theme.tileBorder.setStroke()
        card.stroke()
        drawBadge(m, theme, x: origin.x, midY: size.height / 2, zoom: zoom)

        let ring = M.onRing(150), dots = M.onRing(M.dotAngles[1]), wifi = M.innerCenter
        let letter = NSPoint(x: M.width + M.letterGap + 4, y: M.R - M.letterDrop - 4)
        let callouts: [(NSPoint, Bool, CGFloat, String, String)] = [
            (at(ring.x, ring.y), true, 214, "Battery",
             "Charge, and time left in the gap"),
            (at(dots.x, dots.y), true, 66, "Volume",
             "Five dots, or buds for headphones"),
            (at(wifi.x + 4, wifi.y + 2), false, 214, "Network",
             "Wi-Fi, Ethernet, hotspot, VPN"),
            (at(letter.x, letter.y), false, 66, "Keyboard layout",
             "A flag or letter, if not your usual"),
        ]
        let title = NSFont.systemFont(ofSize: 17, weight: .semibold)
        let body = NSFont.systemFont(ofSize: 14)
        for (point, left, labelY, name, detail) in callouts {
            let edge = left ? origin.x - 60 : origin.x + badgeSize.width + 60
            let line = NSBezierPath()
            line.move(to: point)
            line.line(to: NSPoint(x: edge, y: labelY))
            line.lineWidth = 1.5
            theme.secondary.setStroke()
            line.stroke()
            // A dot with a halo of the card's colour, so it reads on ink and on track
            let pin = NSBezierPath(ovalIn: NSRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
            pin.lineWidth = 3
            theme.tile[0].setStroke()
            pin.stroke()
            theme.secondary.setFill()
            pin.fill()

            let t = text(name, title, theme.text), d = text(detail, body, theme.secondary)
            let w = max(t.size().width, d.size().width)
            let x = left ? edge - 10 - w : edge + 10
            let align: (NSAttributedString) -> CGFloat = { left ? x + w - $0.size().width : x }
            t.draw(at: NSPoint(x: align(t), y: labelY + 1))
            d.draw(at: NSPoint(x: align(d), y: labelY - d.size().height - 1))
        }
    }
    return (size, data)
}

// MARK: - Gallery: one row of cards per part of the badge

struct Tile {
    let title: String
    let detail: String
    let model: StatusIcon.Model
}

let galleries: [(String, Int, [Tile])] = [
    ("battery", 3, [
        Tile(title: "On battery", detail: "Time left in the gap", model: model()),
        Tile(title: "Hovered", detail: "The percentage instead", model: model(label: "72")),
        Tile(title: "On power", detail: "Green, time to full", model: model(battery: battery(0.45, charging: true), label: "1:05")),
        Tile(title: "Low", detail: "Red at 20 % or less", model: model(battery: battery(0.12), label: "0:38")),
        Tile(title: "Low Power Mode", detail: "Yellow", model: model(battery: battery(0.38, lowPower: true), label: "2:40")),
        Tile(title: "Mac working hard", detail: "The arc slowly breathes", model: model(pulse: 0.45)),
    ]),
    ("sound", 3, [
        Tile(title: "Volume", detail: "Five dots", model: model()),
        Tile(title: "Muted", detail: "All dots dimmed", model: model(volume: VolumeState(available: true, level: 0.6, muted: true))),
        Tile(title: "Headphones", detail: "The outer dots become buds", model: model(volume: headphones)),
    ]),
    ("network", 4, [
        Tile(title: "Wi-Fi", detail: "Signal strength", model: model()),
        Tile(title: "Weak Wi-Fi", detail: "Fewer arcs", model: model(network: network(bars: 1))),
        Tile(title: "No internet", detail: "Or Wi-Fi off", model: model(network: network(online: false))),
        Tile(title: "Ethernet", detail: "Or another wired link", model: model(network: network(.wired))),
        Tile(title: "Personal Hotspot", detail: "An iPhone's, in green", model: model(network: network(hotspot: true))),
        Tile(title: "VPN", detail: "Blue, on Wi-Fi…", model: model(network: network(vpn: true))),
        Tile(title: " ", detail: "…on a hotspot…", model: model(network: network(vpn: true, hotspot: true))),
        Tile(title: " ", detail: "…or on Ethernet", model: model(network: network(.wired, vpn: true))),
    ]),
    ("keyboard", 4, [
        Tile(title: "Your usual layout", detail: "Nothing extra", model: model()),
        Tile(title: "Czech", detail: "Its flag inside the ring", model: model(input: .init(letter: "C", language: "cs"))),
        Tile(title: "English", detail: "Its flag inside the ring", model: model(input: .init(letter: "E", language: "en"))),
        Tile(title: "German", detail: "A letter, for the rest", model: model(input: .init(letter: "D", language: "de"))),
    ]),
]

enum Card {
    static let size = NSSize(width: 195, height: 112)
    static let gap: CGFloat = 20
    static let zoom: CGFloat = 3
    static let captionHeight: CGFloat = 50
}

func gallery(_ tiles: [Tile], columns: Int, _ theme: Theme) -> (NSSize, Data) {
    let rows = (tiles.count + columns - 1) / columns
    let cellH = Card.size.height + Card.captionHeight
    let size = NSSize(width: CGFloat(columns) * Card.size.width + CGFloat(columns - 1) * Card.gap,
                      height: CGFloat(rows) * cellH + CGFloat(rows - 1) * Card.gap)
    let title = NSFont.systemFont(ofSize: 15, weight: .semibold)
    let body = NSFont.systemFont(ofSize: 13.5)
    let data = png(size, theme) {
        for (i, tile) in tiles.enumerated() {
            let col = i % columns, row = i / columns
            let x = CGFloat(col) * (Card.size.width + Card.gap)
            let top = size.height - CGFloat(row) * (cellH + Card.gap)
            let rect = NSRect(x: x, y: top - Card.size.height, width: Card.size.width, height: Card.size.height)
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
            gradient(theme.tile, in: shape, vertical: true)
            shape.lineWidth = 1
            theme.tileBorder.setStroke()
            shape.stroke()

            let image = badge(tile.model, theme)
            drawBadge(tile.model, theme, x: rect.midX - image.size.width * Card.zoom / 2,
                      midY: rect.midY, zoom: Card.zoom)

            let t = text(tile.title, title, theme.text)
            t.draw(at: NSPoint(x: x + 4, y: rect.minY - 8 - t.size().height))
            if !tile.detail.isEmpty {
                let d = text(tile.detail, body, theme.secondary)
                d.draw(at: NSPoint(x: x + 4, y: rect.minY - 8 - t.size().height - d.size().height))
            }
        }
    }
    return (size, data)
}

// MARK: - Output

@main
enum RenderPreviews {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var images: [(String, (Theme) -> (NSSize, Data))] = [
            ("hero", hero), ("before-after", beforeAfter), ("anatomy", anatomy),
        ]
        for (name, columns, tiles) in galleries {
            images.append((name, { gallery(tiles, columns: columns, $0) }))
        }

        for (name, render) in images {
            var width: CGFloat = 0
            for theme in themes {
                let (size, data) = render(theme)
                width = size.width
                try data.write(to: out.appendingPathComponent("\(name)-\(theme.name).png"))
            }
            print("  \(name)-{light,dark}.png  (width=\"\(Int(width))\")")
        }
    }
}
