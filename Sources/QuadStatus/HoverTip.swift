import AppKit

/// A tooltip of our own under the status item. The system tooltip on a status
/// bar button didn't reliably appear (macOS 27), so hovering shows this panel.
final class HoverTip: NSResponder {
    /// One row: an optional SF Symbol, drawn in the text colour, then the text.
    struct Line {
        var symbol: String?
        var text: String
    }

    private weak var button: NSStatusBarButton?
    private let text: () -> [Line]
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var pending: Timer?

    /// Called once per hover, just before the tip appears — a place to start
    /// fetching anything slow; `refresh()` then updates the open tip.
    var willShow: (() -> Void)?
    /// Called straight away as the pointer enters (true) or leaves (false).
    var onHover: ((Bool) -> Void)?

    private static let delay: TimeInterval = 0.5   // a little quicker than the system's
    private static let padding = NSSize(width: 8, height: 4)

    init(button: NSStatusBarButton, text: @escaping () -> [Line]) {
        self.button = button
        self.text = text
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        super.init()

        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 5
        background.layer?.masksToBounds = true
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background

        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
        pending?.invalidate()
        pending = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { [weak self] _ in
            self?.willShow?()
            self?.show()
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
        hide()
    }

    func hide() {
        pending?.invalidate()
        pending = nil
        panel.orderOut(nil)
    }

    var isShown: Bool { panel.isVisible }

    /// Re-reads the lines while shown, e.g. when AirPods battery arrives.
    func refresh() { if isShown { show() } }

    private func show() {
        guard let button, let window = button.window else { return }
        let lines = text()
        guard !lines.isEmpty else { return }
        label.attributedStringValue = Self.compose(lines)
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 2 * Self.padding.width,
                          height: label.frame.height + 2 * Self.padding.height)
        label.setFrameOrigin(NSPoint(x: Self.padding.width, y: Self.padding.height))

        // Centred under the icon, kept on screen
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: icon.midX - size.width / 2, y: icon.minY - size.height - 4)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private static func compose(_ lines: [Line]) -> NSAttributedString {
        let font = NSFont.toolTipsFont(ofSize: 0)
        let out = NSMutableAttributedString()
        for (i, line) in lines.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n")) }
            if let name = line.symbol,
               let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular)
                    .applying(.init(paletteColors: [.labelColor]))) {
                let attachment = NSTextAttachment()
                attachment.image = symbol
                // Sit the symbol on the text's baseline, centred on its x-height
                attachment.bounds = NSRect(x: 0, y: (font.capHeight - symbol.size.height) / 2,
                                           width: symbol.size.width, height: symbol.size.height)
                out.append(NSAttributedString(attachment: attachment))
                out.append(NSAttributedString(string: "  "))
            }
            out.append(NSAttributedString(string: line.text))
        }
        out.addAttributes([.font: font, .foregroundColor: NSColor.labelColor],
                          range: NSRange(location: 0, length: out.length))
        return out
    }
}
