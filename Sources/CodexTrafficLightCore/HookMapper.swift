import Foundation

public struct HookEvent: Equatable {
    public var name: String
    public var lastAssistantMessage: String?
    public var cwd: String?
    public var workspace: String?
    public var sessionID: String?
    public var threadID: String?
    public var raw: [String: String]

    public init(
        name: String,
        lastAssistantMessage: String? = nil,
        cwd: String? = nil,
        workspace: String? = nil,
        sessionID: String? = nil,
        threadID: String? = nil,
        raw: [String: String] = [:]
    ) {
        self.name = name
        self.lastAssistantMessage = lastAssistantMessage
        self.cwd = cwd
        self.workspace = workspace
        self.sessionID = sessionID
        self.threadID = threadID
        self.raw = raw
    }

    public static func parse(jsonData: Data, fallbackName: String? = nil) -> HookEvent {
        guard !jsonData.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return HookEvent(name: fallbackName ?? "")
        }

        let stringValue: (String) -> String? = { key in
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            return nil
        }

        var flattened: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                flattened[key] = string
            }
        }

        return HookEvent(
            name: stringValue("hook_event_name") ?? fallbackName ?? "",
            lastAssistantMessage: stringValue("last_assistant_message"),
            cwd: stringValue("cwd") ?? stringValue("current_dir"),
            workspace: stringValue("workspace") ?? stringValue("workspace_root"),
            sessionID: stringValue("session_id") ?? stringValue("conversation_id"),
            threadID: stringValue("thread_id") ?? stringValue("turn_id"),
            raw: flattened
        )
    }
}

public enum HookMapper {
    public static func isQuotaOnlyEvent(_ name: String) -> Bool {
        switch name {
        case "RateLimitsUpdated", "account/rateLimits/updated", "AccountRateLimitsUpdated":
            return true
        default:
            return false
        }
    }

    public static func state(for event: HookEvent) -> LightState {
        switch event.name {
        case "UserPromptSubmit", "PreToolUse":
            return .working
        case "PermissionRequest":
            return .waiting
        case "Stop", "SubagentStop":
            return looksWaiting(event.lastAssistantMessage) ? .waiting : .done
        default:
            return .idle
        }
    }

    public static func looksWaiting(_ message: String?) -> Bool {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let lower = message.lowercased()
        let patterns = [
            "等你",
            "我需要你",
            "我需要.{0,10}(确认|授权|文件|截图|验证码)",
            "要不要",
            "可以吗",
            "行不行",
            "是否需要",
            "是否要",
            "请你(回复|确认一下|授权|登录|发给我|补充一下|选一下)",
            "blocked|waiting for user|permission|approval"
        ]

        return patterns.contains { pattern in
            lower.range(of: pattern, options: [.regularExpression]) != nil
        }
    }
}
