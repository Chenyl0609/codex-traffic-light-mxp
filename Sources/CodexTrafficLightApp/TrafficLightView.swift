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

    private var dragStart: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        let body = layout.bodyRect.nsRect
        drawRoundedGradient(
            body,
            radius: 24,
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
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: paragraph
        ]
        "Codex".draw(in: layout.titleRect.nsRect, withAttributes: attributes)
    }

    private func drawStatusAndQuota() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62),
            .paragraphStyle: paragraph
        ]
        state.label.draw(in: layout.statusRect.nsRect, withAttributes: attributes)

        drawQuotaRow(
            row: layout.quotaRows[0],
            percent: quota?.fiveHourRemainingPercent,
            accent: NSColor(hex: "#61d6c7")
        )
        drawQuotaRow(
            row: layout.quotaRows[1],
            percent: quota?.weeklyRemainingPercent,
            accent: NSColor(hex: "#8bd96b")
        )
    }

    private func drawQuotaRow(row: TrafficLightQuotaRowLayout, percent: Int?, accent: NSColor) {
        let clampedPercent = percent.map { min(max($0, 0), 100) }
        let value = clampedPercent.map { "\($0)%" } ?? "--"
        let labelParagraph = NSMutableParagraphStyle()
        labelParagraph.alignment = .left
        let valueParagraph = NSMutableParagraphStyle()
        valueParagraph.alignment = .right

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.58),
            .paragraphStyle: labelParagraph
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(percent == nil ? 0.42 : 0.72),
            .paragraphStyle: valueParagraph
        ]

        row.label.draw(in: row.labelRect.nsRect, withAttributes: labelAttributes)
        value.draw(in: row.valueRect.nsRect, withAttributes: valueAttributes)

        let barRect = row.progressRect.nsRect
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
        NSColor.white.withAlphaComponent(0.12).setFill()
        barPath.fill()

        guard let clampedPercent, clampedPercent > 0 else { return }
        let fillRect = NSRect(
            x: barRect.minX,
            y: barRect.minY,
            width: barRect.width * CGFloat(clampedPercent) / 100,
            height: barRect.height
        )
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
        accent.withAlphaComponent(0.72).setFill()
        fillPath.fill()
    }

    private func drawLens(center: NSPoint, light: TrafficLightSlot, active: Bool) {
        let base = color(for: light)
        let glowAlpha: CGFloat = active ? 0.30 : 0.04
        let fillAlpha: CGFloat = active ? 1.0 : 0.20
        let rimAlpha: CGFloat = active ? 0.42 : 0.14

        base.withAlphaComponent(glowAlpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)).fill()

        let bulb = NSBezierPath(ovalIn: NSRect(x: center.x - 29, y: center.y - 29, width: 58, height: 58))
        base.withAlphaComponent(fillAlpha).setFill()
        bulb.fill()

        base.withAlphaComponent(rimAlpha).setStroke()
        bulb.lineWidth = 6
        bulb.stroke()

        NSColor.black.withAlphaComponent(0.23).setStroke()
        bulb.lineWidth = 1
        bulb.stroke()

        NSColor.white.withAlphaComponent(active ? 0.24 : 0.08).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 12, y: center.y + 12, width: 22, height: 8)).fill()
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
            onToggleVisibility?()
            return
        }
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
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
