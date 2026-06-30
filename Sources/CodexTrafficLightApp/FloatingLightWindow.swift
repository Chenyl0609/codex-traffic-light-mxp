import Cocoa
import CodexTrafficLightCore

@MainActor
final class FloatingLightWindow {
    let window: NSWindow
    let view: TrafficLightView

    var onDismiss: (() -> Void)?
    var onSilence: (() -> Void)?

    init() {
        let layout = TrafficLightLayout.default
        let size = NSSize(width: layout.windowSize.x, height: layout.windowSize.y)
        view = TrafficLightView(frame: NSRect(origin: .zero, size: size))
        window = NSWindow(
            contentRect: NSRect(x: 1280, y: 450, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view

        view.onDrag = { [weak window] delta in
            guard let window else { return }
            var frame = window.frame
            frame.origin.x += delta.x
            frame.origin.y += delta.y
            window.setFrameOrigin(frame.origin)
        }
        view.onToggleVisibility = { [weak self] in
            self?.onDismiss?()
        }
        view.onDismiss = { [weak self] in
            self?.onDismiss?()
        }
        view.onSilence = { [weak self] in
            self?.onSilence?()
        }
    }

    func apply(state: LightState, quota: QuotaSnapshot?, show: Bool) {
        view.state = state
        view.quota = quota
        if show {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if window.isVisible {
            hide()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
