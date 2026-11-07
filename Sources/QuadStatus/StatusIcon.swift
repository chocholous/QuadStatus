import AppKit

/// The round three-in-one menu bar badge. The composition comes from the
/// "ring + Wi-Fi + signal dots" cluster in the iPhone Duo status bar (iOS 27).
///
/// One ring is cut into two blocks:
///   · top, a 206.4° continuous arc — battery, filling clockwise from the left end
///   · bottom, five dots            — volume, centred on straight down
///   · centre                       — network (Wi-Fi arcs + wedge, or a globe)
///
/// The dots are cellular signal in the original; a Mac has no cellular, so they
/// show system volume instead.
enum StatusIcon {

    /// Every size derives from R, the vertical half-height. The proportions were
    /// measured off the reference art, then re-tuned for menu bar scale — this is
    /// not a uniform scale-down.
    enum M {
        /// The badge is a slightly wide oval. NSStatusBar.thickness says 22pt, but
        /// the menu bar on a notched MacBook is 33pt and the button grows with the
        /// image, so 28pt still leaves a margin above and below.
        static let height: CGFloat = 28
        static let width: CGFloat = 35.2               // 32 + 10 %

        /// The ink is exactly an ellipse with half-axes Rx × R, centred: the battery
        /// arc crosses 0°/90°/180°, reaching the left, right and top edges, and the
        /// middle one of the five dots lands on 270°, reaching the bottom.
        /// Make volumeCount even, or stop the arc crossing the horizontal, and this
        /// no longer holds.
        static let R = height / 2
        static let Rx = width / 2
        static let center = NSPoint(x: Rx, y: R)

        static let ringStroke = 0.230 * R
        static let ringRadius = R - ringStroke / 2       // vertical half-axis of the stroke's centre line
        static let ringRadiusX = Rx - ringStroke / 2     // horizontal half-axis

        /// A point on the ring's centre line at a given angle (degrees).
        static func onRing(_ deg: CGFloat) -> NSPoint {
            let t = deg * .pi / 180
            return NSPoint(x: center.x + ringRadiusX * cos(t), y: center.y + ringRadius * sin(t))
        }
        static let dotRadius = ringStroke / 2        // dot diameter == ring stroke
        static let dim: CGFloat = 0.28               // opacity of anything not lit
        static let trackPulseShare: CGFloat = 0.25   // how much of the fill's pulse the empty track follows

        static let wifiStroke = 0.120 * R
        static let wifiRadii = [0.30 * R, 0.53 * R]
        static let wifiWedge = 0.140 * R
        static let wifiOrigin = NSPoint(x: center.x, y: center.y - 0.28 * R)
        static let wifiArc = (from: CGFloat(46.4), to: CGFloat(133.6))

        static let letterGap = 0.12 * R              // badge edge to keyboard letter
        static let letterScale: CGFloat = 0.78       // of the menu bar font size
        static let letterDrop = 0.22 * R             // below vertical centre

        static let noteGap = 0.25 * R                // badge (or letter) to the AirPods note
        static let noteScale: CGFloat = 0.85         // of the menu bar font size

        // Keyboard flag: a band filling the inside of the ring, around an empty
        // oval that holds the network glyph
        static let flagOpacity: CGFloat = 0.9
        static let flagGap: CGFloat = 0.8            // pt between the ring's inner edge and the flag
        static let flagHoleX: CGFloat = 0.60         // empty oval, as a share of the ring's half-axes
        static let flagHoleY: CGFloat = 0.62
        static let mute: CGFloat = 0.35              // blend toward grey for muted accents

        // Number in the top of the battery arc (percent or minutes): it replaces that
        // stretch of the ring, so the digits stand in the arc's own colour
        static let labelSize = 0.50 * R              // point size of the second digit
        static let digitScales: [CGFloat] = [1.2, 1.0, 0.8]  // first 20 % bigger, third 20 % smaller
        static let labelTop = height - 0.4           // top of the tallest digit's ink
        static let labelRoom: CGFloat = 1.6          // pt of air between the digits and the cut ring's ends
        static let labelWidest = "8:88"              // the cut is sized for this, the widest h:mm

        static let globeRadius = 0.28 * R
        static let innerCenter = NSPoint(x: center.x, y: center.y - 0.05 * R)  // optical centre of the inner glyph

        // MARK: Angles
        //
        // Spacing comes in two tiers: dot to dot is gapUnit, battery block to volume
        // block is 2.6 times that, so you read two functional blocks first and their
        // subdivisions second. The battery arc takes whatever is left, which has to
        // stay over 180° for the ink to reach ±R at the sides.

        static let volumeCount = 5
        static let budScale: CGFloat = 1.45          // AirPod bud vs. a volume dot
        static let hotspotSize = 0.62 * R            // point size of the hotspot symbol

        /// Converts an edge-to-edge gap into an angle on the circle. Each round cap
        /// eats stroke/2 outwards and that has to be added back — otherwise every
        /// degree of gap you ask for is a degree you lose.
        /// On the oval the arc length per degree varies; the mean half-axis is
        /// close enough around the lower half where the gaps live.
        static func angle(edgeGap: CGFloat) -> CGFloat {
            (edgeGap + ringStroke) / ((ringRadius + ringRadiusX) / 2) * 180 / .pi
        }
        /// Edge gap between dots. Was the Wi-Fi stroke width; kept as its own value
        /// so the centre glyph can shrink without packing the dots tighter.
        static let gapUnit = 0.140 * R
        static let dotGap = angle(edgeGap: gapUnit)                // ≈24°
        static let groupGap = angle(edgeGap: gapUnit * 2.6)        // ≈38.5°, keeps the arc past 180°

        // Dot centre spacing is exactly dotGap: centre distance = gap + diameter,
        // the same expression as above.
        static let volumeSpan = CGFloat(volumeCount - 1) * dotGap  // ≈96°
        static let dotAngles = (0..<volumeCount).map {
            270 - volumeSpan / 2 + CGFloat($0) * dotGap
        }

        // The battery arc takes whatever is left
        static let arcSpan = 360 - volumeSpan - 2 * groupGap       // ≈187°
        static let ringStart = 90 + arcSpan / 2                    // left end, fills clockwise
        static let ringEnd = 90 - arcSpan / 2
    }

    /// Equatable lets AppDelegate ask "is this what I drew last time?" directly.
    struct Model: Equatable {
        var battery: BatteryState?
        var volume: VolumeState?
        var network: NetworkState?
        var input: Input?
        /// A short note shown to the right for a few seconds (AirPods battery)
        var note: String?
        /// Digits set into the top of the battery arc (battery percent or minutes left)
        var label: String?
        /// Battery arc opacity, below 1 while it pulses under CPU load or heat
        var pulse: CGFloat = 1
    }

    /// The keyboard layout: a flag for languages that have one, else a letter.
    struct Input: Equatable {
        var letter: String
        var language: String
    }

    private enum Flag { case czech, us }

    private static func flag(for language: String) -> Flag? {
        switch language {
        case "cs": return .czech
        case "en": return .us
        default:   return nil
        }
    }

    static func image(for model: Model, appearance: NSAppearance) -> NSImage {
        // The keyboard letter sits to the right of the badge, in a smaller cut of
        // the menu bar's own font, dropped towards the badge's lower half
        let font = NSFont.menuBarFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize * M.letterScale)
        let flag = model.input.flatMap { flag(for: $0.language) }
        let letter = flag != nil ? nil : model.input.map {
            NSAttributedString(string: $0.letter, attributes: [.font: font])
        }
        let letterSize = letter?.size() ?? .zero
        var width = M.width
        if letter != nil { width += M.letterGap + ceil(letterSize.width) }
        let noteFont = NSFont.menuBarFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize * M.noteScale)
        let note = model.note.map { NSAttributedString(string: $0, attributes: [.font: noteFont]) }
        let noteSize = note?.size() ?? .zero
        let noteX = width + M.noteGap
        if note != nil { width += M.noteGap + ceil(noteSize.width) }

        let image = NSImage(size: NSSize(width: width, height: M.height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                let base = NSColor.labelColor
                if let b = model.battery, b.present { drawRing(b, base, pulse: model.pulse, label: model.label) }
                if let v = model.volume { drawVolumeDots(v, base) }
                if let flag { drawFlagBand(flag) }
                if let n = model.network { drawNetwork(n, base) }
                if let note {
                    let text = NSMutableAttributedString(attributedString: note)
                    text.addAttribute(.foregroundColor, value: base,
                                      range: NSRange(location: 0, length: text.length))
                    text.draw(at: NSPoint(x: noteX, y: (M.height - noteSize.height) / 2))
                }
                if let letter {
                    let text = NSMutableAttributedString(attributedString: letter)
                    text.addAttribute(.foregroundColor, value: base,
                                      range: NSRange(location: 0, length: text.length))
                    text.draw(at: NSPoint(x: M.width + M.letterGap,
                                          y: (M.height - letterSize.height) / 2 - M.letterDrop))
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Keyboard flag

    private static func muted(_ color: NSColor) -> NSColor {
        color.blended(withFraction: M.mute, of: .systemGray) ?? color
    }

    /// The flag fills the inside of the ring as a band: an empty oval in the middle
    /// keeps it clear of the network glyph (Wi-Fi, hotspot, slash), so no colour of
    /// the flag ever touches the glyph.
    private static func drawFlagBand(_ flag: Flag) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset = M.ringStroke / 2 + M.flagGap
        let rx = M.ringRadiusX - inset, ry = M.ringRadius - inset
        let field = NSRect(x: M.center.x - rx, y: M.center.y - ry, width: 2 * rx, height: 2 * ry)

        ctx.saveGState()
        ctx.setAlpha(M.flagOpacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: field).addClip()
        switch flag {
        case .czech: drawCzechFlag(in: field)
        case .us:    drawUSFlag(in: field)
        }
        NSGraphicsContext.restoreGraphicsState()

        ctx.setBlendMode(.destinationOut)
        let hx = M.ringRadiusX * M.flagHoleX, hy = M.ringRadius * M.flagHoleY
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: M.innerCenter.x - hx, y: M.innerCenter.y - hy,
                                    width: 2 * hx, height: 2 * hy)).fill()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// White over red, blue wedge from the hoist to the centre.
    private static func drawCzechFlag(in r: NSRect) {
        NSColor.white.setFill(); r.fill()
        NSColor.systemRed.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2).fill()
        let wedge = NSBezierPath()
        wedge.move(to: NSPoint(x: r.minX, y: r.minY))
        wedge.line(to: NSPoint(x: r.midX, y: r.midY))
        wedge.line(to: NSPoint(x: r.minX, y: r.maxY))
        wedge.close()
        NSColor.systemBlue.setFill(); wedge.fill()
    }

    /// 13 stripes and a blue canton; at menu bar size the stars are only a texture.
    private static func drawUSFlag(in r: NSRect) {
        NSColor.white.setFill(); r.fill()
        let h = r.height / 13
        NSColor.systemRed.setFill()
        for i in stride(from: 0, to: 13, by: 2) {
            NSRect(x: r.minX, y: r.minY + CGFloat(i) * h, width: r.width, height: h).fill()
        }
        let canton = NSRect(x: r.minX, y: r.maxY - 7 * h, width: r.width * 0.45, height: 7 * h)
        NSColor.systemBlue.setFill(); canton.fill()
        NSColor.white.setFill()
        for row in 0..<4 {
            for col in 0..<5 {
                let shift: CGFloat = row.isMultiple(of: 2) ? 0.6 : 1.1
                let x = canton.minX + canton.width * (CGFloat(col) + shift) / 6
                let y = canton.maxY - canton.height * (CGFloat(row) + 0.7) / 4.4
                NSBezierPath(ovalIn: NSRect(x: x - 0.35, y: y - 0.35, width: 0.7, height: 0.7)).fill()
            }
        }
    }

    // MARK: - Brushes

    private static func arc(_ center: NSPoint, _ radius: CGFloat,
                            _ from: CGFloat, _ to: CGFloat,
                            width: CGFloat, color: NSColor, clockwise: Bool = false) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: from, endAngle: to, clockwise: clockwise)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    /// An arc of the oval ring: drawn on the unit circle, then scaled, so the
    /// stroke width stays even all the way round.
    private static func ringArc(_ from: CGFloat, _ to: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(withCenter: .zero, radius: 1, startAngle: from, endAngle: to, clockwise: true)
        var transform = AffineTransform(translationByX: M.center.x, byY: M.center.y)
        transform.scale(x: M.ringRadiusX, y: M.ringRadius)
        path.transform(using: transform)
        path.lineWidth = M.ringStroke
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func dot(at center: NSPoint, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                    width: radius * 2, height: radius * 2)).fill()
    }

    // MARK: - Top block: battery

    private static func drawRing(_ state: BatteryState, _ base: NSColor, pulse: CGFloat, label: String?) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let fill = color(for: state, base: base)
        let ink = fill.withAlphaComponent(fill.alphaComponent * pulse)

        // The digits take the top of the ring for themselves: the band is cut clean
        // through its full width, with room either side, and both ends stay round
        // like the gaps between the volume dots. The cut is sized for the widest
        // label, not this one, so the ring holds still as the text changes.
        var gap: (left: CGFloat, right: CGFloat)?
        var placed: (line: CTLine, origin: CGPoint)?
        if let label {
            let line = labelLine(label, color: ink)
            ctx.textMatrix = .identity
            let bounds = CTLineGetImageBounds(line, ctx)
            let origin = CGPoint(x: M.center.x - bounds.midX, y: M.labelTop - bounds.maxY)
            let widest = CTLineGetImageBounds(labelLine(M.labelWidest, color: ink), ctx)
            let half = widest.width / 2 + M.labelRoom + M.ringStroke / 2
            gap = (ringAngle(atX: M.center.x - half), ringAngle(atX: M.center.x + half))
            placed = (line, origin)
        }

        // The empty track breathes along, but only a fraction as deep as the fill
        let trackPulse = 1 - (1 - pulse) * M.trackPulseShare
        ringArc(M.ringStart, M.ringEnd, around: gap, color: base.withAlphaComponent(M.dim * trackPulse))

        let level = max(0, min(1, state.level))
        if level > 0 { ringArc(M.ringStart, M.ringStart - M.arcSpan * level, around: gap, color: ink) }

        if let placed {
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.textPosition = placed.origin
            CTLineDraw(placed.line, ctx)
            ctx.restoreGState()
        }
    }

    /// The angle (degrees, upper half) where the ring's centre line passes a given x.
    private static func ringAngle(atX x: CGFloat) -> CGFloat {
        acos(max(-1, min(1, (x - M.center.x) / M.ringRadiusX))) * 180 / .pi
    }

    /// A clockwise ring arc with the stretch between the gap's ends left out.
    private static func ringArc(_ from: CGFloat, _ to: CGFloat,
                                around gap: (left: CGFloat, right: CGFloat)?, color: NSColor) {
        guard let gap else { return ringArc(from, to, color: color) }
        if from > gap.left { ringArc(from, max(to, gap.left), color: color) }
        if to < gap.right { ringArc(min(from, gap.right), to, color: color) }
    }

    /// SF Pro Heavy Condensed, as sharp as it stays legible at this size, with
    /// tabular figures so changing digits never shift.
    private static func labelFont(_ size: CGFloat) -> NSFont {
        let condensed = NSFont.systemFont(ofSize: size, weight: .heavy, width: .condensed)
        let tabular = condensed.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: tabular, size: size) ?? condensed
    }

    /// Digits stepping down in size on a shared baseline.
    private static func labelLine(_ label: String, color: NSColor) -> CTLine {
        let text = NSMutableAttributedString()
        // Only digits step down in size; a separator (h:mm) keeps the size before it
        var digit = 0
        for ch in label {
            let size = M.labelSize * M.digitScales[min(max(digit - (ch.isNumber ? 0 : 1), 0),
                                                       M.digitScales.count - 1)]
            if ch.isNumber { digit += 1 }
            text.append(NSAttributedString(string: String(ch),
                                           attributes: [.font: labelFont(size), .foregroundColor: color]))
        }
        return CTLineCreateWithAttributedString(text)
    }

    private static func color(for state: BatteryState, base: NSColor) -> NSColor {
        // Green on power, not only while charging: macOS reports "not charging"
        // for a while after the cable goes in, and again when holding at 80%.
        if state.charging || state.pluggedIn { return .systemGreen }
        if state.lowPowerMode { return .systemYellow }
        if state.level <= 0.20 { return .systemRed }
        return base
    }

    // MARK: - Bottom block: volume

    /// With headphones on, the two outer dots grow into ear cups and the three
    /// between them carry the volume, all in muted purple.
    private static func drawVolumeDots(_ state: VolumeState, _ base: NSColor) {
        let ink = state.headphones ? muted(.systemPurple) : base
        let cups = state.headphones ? [0, M.volumeCount - 1] : []
        let levels = M.volumeCount - cups.count
        let lit = (!state.available || state.muted)
            ? 0 : min(levels, Int(ceil(Double(state.level) * Double(levels))))
        // Muted is one shade fainter than merely sitting at zero
        let off = ink.withAlphaComponent(state.muted ? M.dim * 0.6 : M.dim)

        var level = 0
        for (i, deg) in M.dotAngles.enumerated() {
            let p = M.onRing(deg)
            if cups.contains(i) {
                drawAirPod(at: p, stemToRight: i == 0, color: ink)
            } else {
                dot(at: p, radius: M.dotRadius, color: level < lit ? ink : off)
                level += 1
            }
        }
    }

    // MARK: - Centre: network

    /// A bud with its stem hanging on the inner side, like an AirPod seen from
    /// the front. The bud sits a little above the dot position so the stem
    /// stays inside the canvas.
    private static func drawAirPod(at p: NSPoint, stemToRight: Bool, color: NSColor) {
        let r = M.dotRadius * M.budScale
        let bud = NSPoint(x: p.x, y: p.y + r * 0.7)
        dot(at: bud, radius: r, color: color)

        let dx = (stemToRight ? 1 : -1) * r * 0.45
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: bud.x + dx, y: bud.y - r * 0.3))
        stem.line(to: NSPoint(x: bud.x + dx, y: bud.y - r * 2.0))
        stem.lineWidth = r * 0.9
        stem.lineCapStyle = .round
        color.setStroke()
        stem.stroke()
    }

    /// Over a VPN every network glyph turns blue, whatever the connection.
    private static func drawNetwork(_ state: NetworkState, _ base: NSColor) {
        let vpn: NSColor? = state.vpn ? .systemBlue : nil
        switch state.kind {
        case .wired, .cellular, .other:
            drawGlobe(online: state.online, base: vpn ?? base)
        case .wifi where state.hotspot:
            // Green like the iPhone's hotspot indicator, unless a VPN makes it blue
            drawHotspot(online: state.online, base: vpn ?? muted(.systemGreen))
        case .wifi, .offline:
            drawWiFi(bars: state.bars, online: state.online,
                     slashed: !state.online || !state.wifiPowerOn,
                     base: vpn ?? base)
        }
    }

    private static func drawWiFi(bars: Int, online: Bool, slashed: Bool, base: NSColor) {
        // The innermost shape is a filled sector: swing an arc out from the fan's
        // origin and close back to it, then stroke a thin rounded edge to blunt the tip.
        let wedgeColor = online ? base : base.withAlphaComponent(M.dim)
        let wedge = NSBezierPath()
        wedge.move(to: M.wifiOrigin)
        wedge.appendArc(withCenter: M.wifiOrigin, radius: M.wifiWedge,
                        startAngle: M.wifiArc.from, endAngle: M.wifiArc.to)
        wedge.close()
        wedge.lineWidth = M.wifiStroke * 0.37
        wedge.lineJoinStyle = .round
        wedgeColor.setFill(); wedgeColor.setStroke()
        wedge.fill(); wedge.stroke()

        // Lit from the inside out: one bar is the wedge alone, two adds the middle
        // arc, three adds the outer one
        for (i, r) in M.wifiRadii.enumerated() {
            arc(M.wifiOrigin, r, M.wifiArc.from, M.wifiArc.to, width: M.wifiStroke,
                color: bars >= (i + 2) ? base : base.withAlphaComponent(M.dim))
        }

        if slashed { drawSlash(halfWidth: 0.40 * M.R, aspect: 0.80, base: base) }
    }

    /// Personal Hotspot: Apple's own two-link symbol, tinted like the Wi-Fi glyph.
    private static func drawHotspot(online: Bool, base: NSColor) {
        let ink = online ? base : base.withAlphaComponent(M.dim)
        let config = NSImage.SymbolConfiguration(pointSize: M.hotspotSize, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
        guard let symbol = NSImage(systemSymbolName: "personalhotspot", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let s = symbol.size
        symbol.draw(in: NSRect(x: M.innerCenter.x - s.width / 2, y: M.innerCenter.y - s.height / 2,
                               width: s.width, height: s.height))
        if !online { drawSlash(halfWidth: 0.40 * M.R, aspect: 0.80, base: base) }
    }

    private static func drawGlobe(online: Bool, base: NSColor) {
        let c = M.innerCenter, r = M.globeRadius, w = M.wifiStroke * 0.82
        base.setStroke()

        let outline = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        outline.lineWidth = w
        outline.stroke()

        let equator = NSBezierPath()
        equator.move(to: NSPoint(x: c.x - r, y: c.y))
        equator.line(to: NSPoint(x: c.x + r, y: c.y))
        equator.lineWidth = w * 0.85
        equator.stroke()

        let meridian = NSBezierPath(ovalIn: NSRect(x: c.x - r * 0.48, y: c.y - r,
                                                   width: r * 0.96, height: r * 2))
        meridian.lineWidth = w * 0.85
        meridian.stroke()

        if !online { drawSlash(halfWidth: r * 1.35, aspect: 1.0, base: base) }
    }

    /// The slash across the centre glyph. A wider transparent stroke punches a gap
    /// first, then the solid line goes on top, so the two don't smear together.
    private static func drawSlash(halfWidth: CGFloat, aspect: CGFloat, base: NSColor) {
        let c = M.innerCenter
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c.x - halfWidth, y: c.y + halfWidth * aspect))
        path.line(to: NSPoint(x: c.x + halfWidth, y: c.y - halfWidth * aspect))
        path.lineCapStyle = .round

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setBlendMode(.clear)
        NSColor.black.setStroke()
        path.lineWidth = M.wifiStroke + 1.4
        path.stroke()
        ctx.restoreGState()

        base.setStroke()
        path.lineWidth = M.wifiStroke
        path.stroke()
    }
}
