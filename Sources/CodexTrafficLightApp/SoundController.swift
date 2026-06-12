import Cocoa
import CodexTrafficLightCore

final class SoundController: NSObject {
    private let greenSound = NSSound(named: NSSound.Name("Glass"))
    private let redSound = NSSound(named: NSSound.Name("Basso"))
    private var greenStopTimer: Timer?
    private var redStopTimer: Timer?
    var muted: Bool

    init(muted: Bool) {
        self.muted = muted
        super.init()
    }

    func apply(state: LightState, playPrompt: Bool) {
        if muted {
            stopAll()
            return
        }

        if state != .done {
            stopGreen()
        }
        if state != .waiting {
            stopRed()
        }

        guard playPrompt else { return }
        switch state {
        case .done:
            playGreenForThreeSeconds()
        case .waiting:
            playRedForAlertWindow()
        case .idle, .working, .quit:
            break
        }
    }

    func setMuted(_ nextMuted: Bool) {
        muted = nextMuted
        if muted {
            stopAll()
        }
    }

    private func playGreenForThreeSeconds() {
        guard let greenSound else { return }
        greenStopTimer?.invalidate()
        greenSound.stop()
        greenSound.currentTime = 0
        greenSound.loops = true
        greenSound.play()
        greenStopTimer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(stopGreen), userInfo: nil, repeats: false)
    }

    private func playRedForAlertWindow() {
        guard let redSound else { return }
        redStopTimer?.invalidate()
        redSound.stop()
        redSound.currentTime = 0
        redSound.loops = true
        redSound.play()
        redStopTimer = Timer.scheduledTimer(timeInterval: Defaults.waitingAlertSeconds, target: self, selector: #selector(stopRed), userInfo: nil, repeats: false)
    }

    @objc private func stopGreen() {
        greenStopTimer?.invalidate()
        greenStopTimer = nil
        greenSound?.loops = false
        greenSound?.stop()
        greenSound?.currentTime = 0
    }

    @objc private func stopRed() {
        redStopTimer?.invalidate()
        redStopTimer = nil
        redSound?.loops = false
        redSound?.stop()
        redSound?.currentTime = 0
    }

    func stopAll() {
        stopGreen()
        stopRed()
    }
}
