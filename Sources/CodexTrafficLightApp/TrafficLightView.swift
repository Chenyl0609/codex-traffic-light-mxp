import Cocoa
import CodexTrafficLightCore

final class TrafficLightView: NSView {
    private let layout = TrafficLightLayout.default

    var state: LightState = .idle {
        didSet { needsDisplay = true }
    }
    var quota: QuotaSnapshot? {
        didSet { needsDisplay = true }
    }
    var blinkOn = true {
        didSet { needsDisplay = true }
    }
    var waitingAlertActive = false {
        didSet { needsDisplay = true }
    }
    var onDrag: ((NSPoint) -> Void)?
    var onToggleVisibility: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var dragStart: NSPoint?
    private var singleClickTimer: Timer?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let body = layout.bodyRect.nsRect
        drawRoundedGradient(
            body,
            radius: 16,
            top: NSColor(hex: "#34383d"),
            bottom: NSColor(hex: "#171a1e"),
            stroke: NSColor.white.withAlphaComponent(0.15),
            width: 1
        )

        drawTitle()

        let centers: [(TrafficLightSlot, NSPoint)] = [
            (.red, layout.center(for: .red).nsPoint),
            (.yellow, layout.center(for: .yellow).nsPoint),
            (.green, layout.center(for: .green).nsPoint)
        ]
        for (light, center) in centers {
            drawLens(center: center, light: light, active: isVisible(light))
        }
        drawStatusAndQuota()
    }

    private func activeLight() -> TrafficLightSlot? {
        switch state {
        case .waiting: return .red
        case .working: return .yellow
        case .done: return .green
        case .idle, .quit: return nil
        }
    }

    private func isVisible(_ light: TrafficLightSlot) -> Bool {
        guard activeLight() == light else { return false }
        return state == .waiting && waitingAlertActive ? blinkOn : true
    }

    private func color(for light: TrafficLightSlot) -> NSColor {
        switch light {
        case .red: return NSColor(hex: "#f3423b")
        case .yellow: return NSColor(hex: "#ffd441")
        case .green: return NSColor(hex: "#55d34d")
        }
    }

    private func drawTitle() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph
        ]
        "Claude".draw(in: layout.titleRect.nsRect, withAttributes: attributes)
    }

    private func drawStatusAndQuota() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62),
            .paragraphStyle: paragraph
        ]
        state.label.draw(in: layout.statusRect.nsRect, withAttributes: attributes)
    }

    private func drawLens(center: NSPoint, light: TrafficLightSlot, active: Bool) {
        let base = color(for: light)
        let glowAlpha: CGFloat = active ? 0.35 : 0.0
        let fillAlpha: CGFloat = active ? 1.0 : 0.20
        let rimAlpha: CGFloat = active ? 0.42 : 0.14

        base.withAlphaComponent(glowAlpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - layout.lensGlowRadius, y: center.y - layout.lensGlowRadius, width: layout.lensGlowRadius * 2, height: layout.lensGlowRadius * 2)).fill()

        let bulb = NSBezierPath(ovalIn: NSRect(x: center.x - layout.lensBulbRadius, y: center.y - layout.lensBulbRadius, width: layout.lensBulbRadius * 2, height: layout.lensBulbRadius * 2))
        base.withAlphaComponent(fillAlpha).setFill()
        bulb.fill()

        base.withAlphaComponent(rimAlpha).setStroke()
        bulb.lineWidth = 4
        bulb.stroke()

        NSColor.black.withAlphaComponent(0.23).setStroke()
        bulb.lineWidth = 1
        bulb.stroke()

        NSColor.white.withAlphaComponent(active ? 0.24 : 0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 8, y: center.y + 8, width: 14, height: 5)).fill()
    }

    private func drawRoundedGradient(_ rect: NSRect, radius: CGFloat, top: NSColor, bottom: NSColor, stroke: NSColor, width: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(starting: bottom, ending: top)?.draw(in: rect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
        stroke.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            singleClickTimer?.invalidate()
            singleClickTimer = nil
            onToggleVisibility?()
            return
        }
        if event.clickCount == 1 {
            singleClickTimer?.invalidate()
            singleClickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.onDismiss?() }
            }
        }
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        singleClickTimer?.invalidate()
        singleClickTimer = nil
        let current = event.locationInWindow
        onDrag?(NSPoint(x: current.x - dragStart.x, y: current.y - dragStart.y))
    }
}

private extension TrafficLightPoint {
    var nsPoint: NSPoint {
        NSPoint(x: x, y: y)
    }
}

private extension TrafficLightRect {
    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
