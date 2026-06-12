import Foundation

public enum ContextResolver {
    public static func taskID(explicitTaskID: String?, workspace: String?, hookEvent: HookEvent? = nil) -> String {
        if let explicitTaskID, !explicitTaskID.isEmpty {
            return explicitTaskID
        }
        if let sessionID = hookEvent?.sessionID, !sessionID.isEmpty {
            return "session:\(sessionID)"
        }
        if let threadID = hookEvent?.threadID, !threadID.isEmpty {
            return "thread:\(threadID)"
        }
        let workspaceValue = workspace ?? hookEvent?.workspace ?? hookEvent?.cwd ?? FileManager.default.currentDirectoryPath
        return "workspace:\(workspaceValue):default"
    }

    public static func workspace(explicitWorkspace: String?, hookEvent: HookEvent? = nil) -> String {
        explicitWorkspace ?? hookEvent?.workspace ?? hookEvent?.cwd ?? FileManager.default.currentDirectoryPath
    }
}
