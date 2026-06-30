import Foundation

public struct HookBridgeResult: Equatable, Sendable {
    public var eventName: String
    public var state: LightState
    public var taskID: String
    public var workspace: String?
    public var quotaSummary: String?
    public var updatedTask: Bool

    public init(
        eventName: String,
        state: LightState,
        taskID: String,
        workspace: String?,
        quotaSummary: String?,
        updatedTask: Bool
    ) {
        self.eventName = eventName
        self.state = state
        self.taskID = taskID
        self.workspace = workspace
        self.quotaSummary = quotaSummary
        self.updatedTask = updatedTask
    }
}

public enum HookBridge {
    @discardableResult
    public static func apply(
        input: Data,
        fallbackName: String?,
        store: StateStore = StateStore(),
        now: Date = Date()
    ) throws -> HookBridgeResult {
        let event = HookEvent.parse(jsonData: input, fallbackName: fallbackName)
        let quota = QuotaExtractor.extract(from: input)
        let quotaOnly = HookMapper.isQuotaOnlyEvent(event.name)
        let workspace = ContextResolver.workspace(explicitWorkspace: nil, hookEvent: event)
        let taskID = ContextResolver.taskID(explicitTaskID: nil, workspace: workspace, hookEvent: event)

        let workspaceStore: StateStore
        if !workspace.isEmpty {
            workspaceStore = StateStore(stateURL: StateStore.workspaceStateURL(workspace: workspace))
        } else {
            workspaceStore = store
        }

        var snapshot = workspaceStore.read()

        if let quota {
            snapshot = try workspaceStore.updateQuota(
                fiveHourPercent: quota.fiveHourRemainingPercent,
                weeklyPercent: quota.weeklyRemainingPercent,
                source: "codex-hook",
                now: now
            )
            if workspaceStore.stateURL != store.stateURL {
                _ = try? store.updateQuota(
                    fiveHourPercent: quota.fiveHourRemainingPercent,
                    weeklyPercent: quota.weeklyRemainingPercent,
                    source: "codex-hook",
                    now: now
                )
            }
        }

        if quotaOnly {
            return HookBridgeResult(
                eventName: event.name,
                state: snapshot.aggregateState == .quit ? .idle : snapshot.aggregateState,
                taskID: taskID,
                workspace: workspace,
                quotaSummary: quota?.summary,
                updatedTask: false
            )
        }

        let state = HookMapper.state(for: event)
        let message = event.lastAssistantMessage ?? "Cloud Code light: \(state.rawValue)"
        snapshot = try workspaceStore.updateTask(
            taskID: taskID,
            state: state,
            workspace: workspace,
            source: "codex-hook",
            hookEventName: event.name,
            message: message,
            now: now
        )

        if workspaceStore.stateURL != store.stateURL {
            _ = try? store.updateTask(
                taskID: taskID,
                state: state,
                workspace: workspace,
                source: "codex-hook",
                hookEventName: event.name,
                message: message,
                now: now
            )
        }

        return HookBridgeResult(
            eventName: event.name,
            state: state,
            taskID: taskID,
            workspace: workspace,
            quotaSummary: quota?.summary,
            updatedTask: true
        )
    }
}
