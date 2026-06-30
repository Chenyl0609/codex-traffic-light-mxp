import Cocoa
import CodexTrafficLightCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, StatusBarControllerDelegate {
    private let store = StateStore()
    private let preferencesStore = PreferencesStore()
    private lazy var statusBar = StatusBarController()
    private lazy var floatingWindow = FloatingLightWindow()
    private lazy var soundController = SoundController(muted: preferences.muted)
    private var preferences = AppPreferences.defaults()
    private var currentState: LightState = .idle
    private var currentQuota: QuotaSnapshot?
    private var lastModified = Date.distantPast
    private var blinkTimer: Timer?
    private var waitingBlinkStopTimer: Timer?
    private var idleTimer: Timer?
    private var quotaTimer: Timer?
    private var vsCodeCheckTimer: Timer?
    private let quotaRefreshCoordinator = QuotaRefreshCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = preferencesStore.read()
        soundController = SoundController(muted: preferences.muted)
        statusBar.delegate = self
        floatingWindow.onDismiss = { [weak self] in
            self?.dismissAlert()
        }
        floatingWindow.onSilence = { [weak self] in
            self?.silenceAlert()
        }

        let snapshot = store.read()
        currentQuota = snapshot.quota
        currentState = snapshot.aggregateState == .quit ? .idle : snapshot.aggregateState
        apply(state: currentState, playPrompt: false, source: .startup)

        Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(pollStateTimerFired), userInfo: nil, repeats: true)
        blinkTimer = Timer.scheduledTimer(timeInterval: 0.52, target: self, selector: #selector(blinkTimerFired), userInfo: nil, repeats: true)
        Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(quotaTimerFired), userInfo: nil, repeats: false)
        quotaTimer = Timer.scheduledTimer(timeInterval: Defaults.appServerQuotaRefreshSeconds, target: self, selector: #selector(quotaTimerFired), userInfo: nil, repeats: true)
        vsCodeCheckTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(vsCodeCheckFired), userInfo: nil, repeats: true)

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.control),
                  event.modifierFlags.contains(.option),
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "l" else { return }
            DispatchQueue.main.async { [weak self] in
                self?.floatingWindow.toggle()
            }
        }

        checkHooksConfiguration()
    }

    private func checkHooksConfiguration() {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              !hooks.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Claude Code Hooks 未配置"
            alert.informativeText = "Cloud Code Light 需要 Claude Code 的 Hooks 才能自动检测状态。\n\n请运行 install.command 或手动将 Docs/hooks-claude-code.example.json 中的配置合并到 ~/.claude/settings.json"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
    }

    private enum StateSource {
        case startup
        case file
        case user
        case timer
    }

    @objc private func pollStateTimerFired() {
        pollState()
    }

    @objc private func quotaTimerFired() {
        refreshQuotaFromAppServer()
    }

    @objc private func vsCodeCheckFired() {
        guard currentState != .idle && currentState != .quit else { return }
        guard !floatingWindow.window.isVisible else { return }
        if isVSCodeFrontmost() { return }
        floatingWindow.show()
    }

    private func isVSCodeFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.microsoft.VSCode"
    }

    private func refreshQuotaFromAppServer() {
        guard quotaRefreshCoordinator.beginRefresh() else { return }
        let stateURL = store.stateURL
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let backgroundStore = StateStore(stateURL: stateURL)
            do {
                let snapshot = try CodexAppServerQuotaCollector().fetchAndUpdate(store: backgroundStore)
                DispatchQueue.main.async {
                    self?.handleQuotaSnapshot(snapshot)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.handleQuotaRefreshFailure(error)
                }
            }
        }
    }

    private func handleQuotaSnapshot(_ snapshot: StateSnapshot) {
        quotaRefreshCoordinator.endRefresh(success: true)
        currentQuota = snapshot.quota
        if snapshot.aggregateState != .quit {
            currentState = snapshot.aggregateState
        }
        updateStatusOnly()
    }

    private func handleQuotaRefreshFailure(_ error: Error) {
        if let line = quotaRefreshCoordinator.failureLogLine(error: error) {
            AppDelegate.appendQuotaLog(line)
        }
        quotaRefreshCoordinator.endRefresh(success: false)
    }

    private nonisolated static func appendQuotaLog(_ line: String) {
        let url = StateStore.defaultSupportDirectory().appendingPathComponent("quota-mxp.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data = "\(timestamp) \(line)\n".data(using: .utf8)!
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func pollState() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: store.stateURL.path)
        let modified = attributes?[.modificationDate] as? Date ?? Date.distantPast
        guard modified != lastModified else { return }
        lastModified = modified

        let snapshot = store.read()
        let next = snapshot.aggregateState
        currentQuota = snapshot.quota
        if next == .quit {
            terminate()
            return
        }
        if next != currentState {
            apply(state: next, playPrompt: true, source: .file)
        } else {
            updateStatusOnly()
        }
    }

    private func apply(state: LightState, playPrompt: Bool, source: StateSource) {
        currentState = state
        statusBar.apply(state: state, muted: preferences.muted, quota: currentQuota)
        floatingWindow.apply(state: state, quota: currentQuota, show: shouldShowFloatingWindow(for: state, source: source))
        soundController.apply(state: state, playPrompt: playPrompt)

        if state == .waiting {
            startWaitingBlink()
        } else {
            stopWaitingBlink()
        }
        if state == .done {
            startIdleTimer()
        } else {
            idleTimer?.invalidate()
            idleTimer = nil
        }
    }

    private func updateStatusOnly() {
        statusBar.apply(state: currentState, muted: preferences.muted, quota: currentQuota)
        floatingWindow.view.state = currentState
        floatingWindow.view.quota = currentQuota
    }

    private func shouldShowFloatingWindow(for state: LightState, source: StateSource) -> Bool {
        if source == .user { return preferences.showFloatingWindow }
        switch state {
        case .waiting, .working, .done:
            return true
        case .idle, .quit:
            return floatingWindow.window.isVisible && preferences.showFloatingWindow
        }
    }

    private func startWaitingBlink() {
        waitingBlinkStopTimer?.invalidate()
        floatingWindow.view.waitingAlertActive = true
        floatingWindow.view.blinkOn = true
        waitingBlinkStopTimer = Timer.scheduledTimer(timeInterval: Defaults.waitingAlertSeconds, target: self, selector: #selector(waitingBlinkStopTimerFired), userInfo: nil, repeats: false)
    }

    private func stopWaitingBlink() {
        waitingBlinkStopTimer?.invalidate()
        waitingBlinkStopTimer = nil
        floatingWindow.view.waitingAlertActive = false
        floatingWindow.view.blinkOn = true
    }

    @objc private func waitingBlinkStopTimerFired() {
        floatingWindow.view.waitingAlertActive = false
        floatingWindow.view.blinkOn = true
    }

    @objc private func blinkTimerFired() {
        blink()
    }

    private func blink() {
        guard currentState == .waiting && floatingWindow.view.waitingAlertActive else { return }
        floatingWindow.view.blinkOn.toggle()
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(timeInterval: Defaults.doneAutoIdleSeconds, target: self, selector: #selector(idleTimerFired), userInfo: nil, repeats: false)
    }

    @objc private func idleTimerFired() {
        guard currentState == .done else { return }
        let snapshot = try? store.clear()
        currentQuota = snapshot?.quota
        apply(state: .idle, playPrompt: false, source: .timer)
    }

    func statusBarDidRequestState(_ state: LightState) {
        let taskID = ContextResolver.taskID(explicitTaskID: "manual", workspace: FileManager.default.currentDirectoryPath)
        _ = try? store.updateTask(
            taskID: taskID,
            state: state,
            workspace: FileManager.default.currentDirectoryPath,
            source: "menu",
            hookEventName: nil,
            message: "Cloud Code light: \(state.rawValue)"
        )
        let snapshot = store.read()
        currentQuota = snapshot.quota
        apply(state: snapshot.aggregateState, playPrompt: true, source: .user)
    }

    func statusBarDidRequestClear() {
        let snapshot = try? store.clear()
        currentQuota = snapshot?.quota
        apply(state: .idle, playPrompt: false, source: .user)
    }

    func statusBarDidRequestToggleFloatingWindow() {
        floatingWindow.toggle()
    }

    func statusBarDidRequestToggleMute() {
        preferences.muted.toggle()
        preferences.updatedAt = Date()
        preferencesStore.write(preferences)
        soundController.setMuted(preferences.muted)
        updateStatusOnly()
    }

    func statusBarDidRequestQuit() {
        terminate()
    }

    func statusBarDidRequestAbout() {
        let alert = NSAlert()
        alert.messageText = "Cloud Code Light"
        alert.informativeText = "版本 1.0\n专为 Claude Code + VS Code 打造的 macOS 状态灯\n\nGitHub: github.com/Chenyl0609/codex-traffic-light-mxp"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }

    private func dismissAlert() {
        soundController.stopAll()
        stopWaitingBlink()
        floatingWindow.hide()
        openVSCode()
    }

    private func silenceAlert() {
        soundController.stopAll()
        stopWaitingBlink()
    }

    private func openVSCode() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code"]
        try? process.run()
    }

    private func terminate() {
        soundController.stopAll()
        quotaTimer?.invalidate()
        NSApp.terminate(nil)
    }
}
