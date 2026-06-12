# Codex Quota Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show Codex 5-hour and 1-week remaining quota percentages under the floating traffic-light status text.

**Architecture:** Extend the existing `state.json` snapshot with an optional `quota` object, then render that object in the AppKit-drawn floating widget. Keep quota ingestion separate from the traffic-light state machine so hooks and light aggregation keep working even when quota data is missing or stale.

**Tech Stack:** Swift 6, SwiftPM, AppKit custom drawing, existing local JSON state file, existing CLI binaries `codex-light-mxp` and `codex-light-hook-mxp`.

---

## Current Context

- `TrafficLightView` draws the entire companion widget by hand in AppKit.
- `FloatingLightWindow` currently uses a `116 x 298` borderless window.
- `AppDelegate` polls `StateStore.stateURL` every 0.25 seconds and pushes `aggregateState` into the menu bar and floating view.
- `StateSnapshot` currently contains `aggregate_state`, `updated_at`, and `tasks`.
- Recent local Codex logs show `account/rateLimits/updated` app-server events, but the stable payload contract is not exposed by the project. The first implementation should not depend solely on parsing private logs.

## Data Contract

Add an optional quota model to `StateSnapshot`:

```json
{
  "aggregate_state": "waiting",
  "updated_at": 1781189000.123,
  "quota": {
    "five_hour_remaining_percent": 72,
    "weekly_remaining_percent": 48,
    "source": "cli",
    "updated_at": 1781189000.123
  },
  "tasks": {}
}
```

Rules:

- Percent values are integers clamped to `0...100`.
- `quota` is optional for backwards compatibility.
- Missing quota renders as `--` with empty progress bars.
- Stale quota can still be displayed, but the menu should expose its source and update time later if needed.
- `clear` should clear task state but preserve quota by default, because quota is account-level, not task-level.

## File Structure

- Modify `Sources/CodexTrafficLightCore/Models.swift`
  - Add `QuotaSnapshot`.
  - Add `quota: QuotaSnapshot?` to `StateSnapshot`.
  - Preserve old JSON decoding by making quota optional.
- Modify `Sources/CodexTrafficLightCore/StateStore.swift`
  - Add `updateQuota(fiveHourPercent:weeklyPercent:source:now:)`.
  - Ensure `clear()` preserves existing quota unless a new explicit reset command is added.
- Modify `Sources/codex-light-mxp/main.swift`
  - Add CLI command `quota`.
  - Support `codex-light-mxp quota --five-hour 72 --weekly 48`.
  - Keep `status --json` as the verification path.
- Modify `Sources/CodexTrafficLightApp/TrafficLightView.swift`
  - Add `var quota: QuotaSnapshot?`.
  - Increase layout height and draw two rows below the status text.
- Modify `Sources/CodexTrafficLightApp/FloatingLightWindow.swift`
  - Increase window/view height to fit quota rows.
- Modify `Sources/CodexTrafficLightApp/AppDelegate.swift`
  - Pass `snapshot.quota` into `StatusBarController` and `TrafficLightView`.
- Modify `Sources/CodexTrafficLightApp/StatusBarController.swift`
  - Add quota to tooltip/menu title only if it exists.
- Modify `Sources/codex-light-mxp-tests/main.swift`
  - Add model, store, CLI contract, and rendering-layout-adjacent tests.
- Modify `README.md`
  - Document quota CLI and runtime JSON shape.

## Task 1: Core Quota Model

**Files:**
- Modify: `Sources/CodexTrafficLightCore/Models.swift`
- Test: `Sources/codex-light-mxp-tests/main.swift`

- [ ] **Step 1: Write failing tests**

Add tests:

```swift
func testQuotaSnapshotClampsPercentValues() throws {
    let quota = QuotaSnapshot(
        fiveHourRemainingPercent: 140,
        weeklyRemainingPercent: -12,
        source: "test",
        updatedAt: Date(timeIntervalSince1970: 6_000)
    )
    try expectEqual(quota.fiveHourRemainingPercent, 100, "five hour percent should clamp high values")
    try expectEqual(quota.weeklyRemainingPercent, 0, "weekly percent should clamp low values")
}

func testStateSnapshotDecodesWithoutQuota() throws {
    let body = """
    {
      "aggregate_state": "idle",
      "updated_at": 6000,
      "tasks": {}
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let snapshot = try decoder.decode(StateSnapshot.self, from: Data(body.utf8))
    try expectEqual(snapshot.quota == nil, true, "quota should be optional for existing state files")
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache SWIFTPM_CACHE_PATH=.build/swiftpm-cache swift run codex-light-mxp-tests
```

Expected: build fails because `QuotaSnapshot` and `StateSnapshot.quota` do not exist.

- [ ] **Step 3: Implement model**

Add to `Models.swift`:

```swift
public struct QuotaSnapshot: Codable, Equatable {
    public var fiveHourRemainingPercent: Int
    public var weeklyRemainingPercent: Int
    public var source: String
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case fiveHourRemainingPercent = "five_hour_remaining_percent"
        case weeklyRemainingPercent = "weekly_remaining_percent"
        case source
        case updatedAt = "updated_at"
    }

    public init(
        fiveHourRemainingPercent: Int,
        weeklyRemainingPercent: Int,
        source: String,
        updatedAt: Date
    ) {
        self.fiveHourRemainingPercent = min(100, max(0, fiveHourRemainingPercent))
        self.weeklyRemainingPercent = min(100, max(0, weeklyRemainingPercent))
        self.source = source
        self.updatedAt = updatedAt
    }
}
```

Update `StateSnapshot`:

```swift
public struct StateSnapshot: Codable, Equatable {
    public var aggregateState: LightState
    public var updatedAt: Date
    public var quota: QuotaSnapshot?
    public var tasks: [String: TaskState]

    enum CodingKeys: String, CodingKey {
        case aggregateState = "aggregate_state"
        case updatedAt = "updated_at"
        case quota
        case tasks
    }

    public init(aggregateState: LightState, updatedAt: Date, quota: QuotaSnapshot? = nil, tasks: [String: TaskState]) {
        self.aggregateState = aggregateState
        self.updatedAt = updatedAt
        self.quota = quota
        self.tasks = tasks
    }
}
```

Update `empty()` and `pruningExpiredDone()` to pass `quota`.

- [ ] **Step 4: Run tests**

Run the same test command.

Expected: all existing tests plus the two new quota tests pass.

## Task 2: State Store Quota Updates

**Files:**
- Modify: `Sources/CodexTrafficLightCore/StateStore.swift`
- Test: `Sources/codex-light-mxp-tests/main.swift`

- [ ] **Step 1: Write failing tests**

Add:

```swift
func testUpdateQuotaPreservesTasksAndAggregateState() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-light-mxp-quota-store-\(UUID().uuidString)", isDirectory: true)
    let store = StateStore(stateURL: directory.appendingPathComponent("state.json"))
    let now = Date(timeIntervalSince1970: 7_000)
    _ = try store.updateTask(
        taskID: "task-1",
        state: .working,
        workspace: "/tmp/project",
        source: "test",
        hookEventName: "PreToolUse",
        message: nil,
        now: now
    )

    let snapshot = try store.updateQuota(
        fiveHourPercent: 72,
        weeklyPercent: 48,
        source: "test",
        now: now.addingTimeInterval(1)
    )

    try expectEqual(snapshot.aggregateState, .working, "quota update should not change aggregate state")
    try expectEqual(snapshot.tasks.count, 1, "quota update should preserve tasks")
    try expectEqual(snapshot.quota?.fiveHourRemainingPercent, 72, "quota should store five hour percent")
    try expectEqual(snapshot.quota?.weeklyRemainingPercent, 48, "quota should store weekly percent")
}

func testClearPreservesQuota() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-light-mxp-quota-clear-\(UUID().uuidString)", isDirectory: true)
    let store = StateStore(stateURL: directory.appendingPathComponent("state.json"))
    let now = Date(timeIntervalSince1970: 8_000)
    _ = try store.updateQuota(fiveHourPercent: 72, weeklyPercent: 48, source: "test", now: now)
    let snapshot = try store.clear(now: now.addingTimeInterval(1))
    try expectEqual(snapshot.aggregateState, .idle, "clear should still idle tasks")
    try expectEqual(snapshot.quota?.fiveHourRemainingPercent, 72, "clear should preserve account quota")
}
```

- [ ] **Step 2: Run test to verify failure**

Expected: `StateStore.updateQuota` is missing.

- [ ] **Step 3: Implement store method**

Add to `StateStore`:

```swift
@discardableResult
public func updateQuota(
    fiveHourPercent: Int,
    weeklyPercent: Int,
    source: String,
    now: Date = Date()
) throws -> StateSnapshot {
    var snapshot = read().pruningExpiredDone(now: now)
    snapshot.quota = QuotaSnapshot(
        fiveHourRemainingPercent: fiveHourPercent,
        weeklyRemainingPercent: weeklyPercent,
        source: source,
        updatedAt: now
    )
    snapshot.aggregateState = snapshot.computedAggregate(now: now)
    snapshot.updatedAt = now
    try write(snapshot)
    return snapshot
}
```

Update `clear(now:)`:

```swift
public func clear(now: Date = Date()) throws -> StateSnapshot {
    let existingQuota = read().quota
    let snapshot = StateSnapshot(aggregateState: .idle, updatedAt: now, quota: existingQuota, tasks: [:])
    try write(snapshot)
    return snapshot
}
```

- [ ] **Step 4: Run tests**

Expected: store tests pass.

## Task 3: CLI Quota Command

**Files:**
- Modify: `Sources/codex-light-mxp/main.swift`
- Test: `Sources/codex-light-mxp-tests/main.swift`

- [ ] **Step 1: Write parser tests**

Because the CLI parser currently lives in the executable target, keep tests focused on command contract strings unless parser extraction is chosen. Add a test that locks the command name and expected syntax in `CommandContract`:

```swift
func testQuotaCommandContract() throws {
    try expectEqual(CommandContract.quotaCommandName, "quota", "quota command should be stable")
}
```

Add to `CommandContract`:

```swift
public static let quotaCommandName = "quota"
```

- [ ] **Step 2: Extend CLI options**

Modify `CLIOptions`:

```swift
struct CLIOptions {
    var taskID: String?
    var workspace: String?
    var json = false
    var fiveHourPercent: Int?
    var weeklyPercent: Int?
    var command: String?
}
```

Extend `usage()`:

```text
Usage: codex-light-mxp [--task <task-id>] [--workspace <path>] [--json] <working|done|waiting|idle|status|clear|quit>
       codex-light-mxp quota --five-hour <0-100> --weekly <0-100> [--json]
```

Add parser cases:

```swift
case "--five-hour":
    index += 1
    guard index < arguments.count, let value = Int(arguments[index]) else {
        throw StateStoreError.invalidState("--five-hour requires an integer")
    }
    options.fiveHourPercent = value
case "--weekly":
    index += 1
    guard index < arguments.count, let value = Int(arguments[index]) else {
        throw StateStoreError.invalidState("--weekly requires an integer")
    }
    options.weeklyPercent = value
```

- [ ] **Step 3: Add command handling**

Add before the default state branch:

```swift
case CommandContract.quotaCommandName:
    guard let fiveHourPercent = options.fiveHourPercent,
          let weeklyPercent = options.weeklyPercent else {
        throw StateStoreError.invalidState("quota requires --five-hour and --weekly")
    }
    let snapshot = try store.updateQuota(
        fiveHourPercent: fiveHourPercent,
        weeklyPercent: weeklyPercent,
        source: "cli"
    )
    try printSnapshot(snapshot, json: options.json)
```

- [ ] **Step 4: Manual smoke test**

Run:

```bash
STATE=/tmp/codex-light-quota-state.json
CODEX_TRAFFIC_LIGHT_STATE_PATH="$STATE" .build/release/codex-light-mxp clear
CODEX_TRAFFIC_LIGHT_STATE_PATH="$STATE" .build/release/codex-light-mxp quota --five-hour 72 --weekly 48 --json
```

Expected JSON contains:

```json
"quota" : {
  "five_hour_remaining_percent" : 72,
  "weekly_remaining_percent" : 48,
  "source" : "cli"
}
```

## Task 4: Floating Widget Layout

**Files:**
- Modify: `Sources/CodexTrafficLightApp/TrafficLightView.swift`
- Modify: `Sources/CodexTrafficLightApp/FloatingLightWindow.swift`

- [ ] **Step 1: Add quota property**

Add to `TrafficLightView`:

```swift
var quota: QuotaSnapshot? {
    didSet { needsDisplay = true }
}
```

- [ ] **Step 2: Update window height**

Change `FloatingLightWindow` dimensions from `116 x 298` to `116 x 342`:

```swift
view = TrafficLightView(frame: NSRect(x: 0, y: 0, width: 116, height: 342))
window = NSWindow(
    contentRect: NSRect(x: 1280, y: 496, width: 116, height: 342),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
```

- [ ] **Step 3: Adjust lamp layout**

Use fixed centers that preserve the original look while freeing bottom space:

```swift
let centers = [
    ("red", NSPoint(x: bounds.midX, y: bounds.maxY - 104)),
    ("yellow", NSPoint(x: bounds.midX, y: bounds.maxY - 184)),
    ("green", NSPoint(x: bounds.midX, y: bounds.maxY - 264))
]
```

Move footer text to:

```swift
state.label.draw(in: NSRect(x: 8, y: 52, width: bounds.width - 16, height: 22), withAttributes: attributes)
```

- [ ] **Step 4: Draw quota rows**

Add:

```swift
private func drawQuota() {
    let baseY: CGFloat = 18
    drawQuotaRow(label: "5小时", percent: quota?.fiveHourRemainingPercent, y: baseY + 18, accent: NSColor(hex: "#61d6c7"))
    drawQuotaRow(label: "1周", percent: quota?.weeklyRemainingPercent, y: baseY, accent: NSColor(hex: "#8bd96b"))
}
```

Add `drawQuotaRow`:

```swift
private func drawQuotaRow(label: String, percent: Int?, y: CGFloat, accent: NSColor) {
    let valueText = percent.map { "\($0)%" } ?? "--"
    let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.48)
    ]
    let valueAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.70)
    ]
    label.draw(in: NSRect(x: 28, y: y + 6, width: 28, height: 12), withAttributes: labelAttributes)
    valueText.draw(in: NSRect(x: 66, y: y + 6, width: 26, height: 12), withAttributes: valueAttributes)

    let track = NSRect(x: 28, y: y + 1, width: 60, height: 3)
    NSColor.white.withAlphaComponent(0.11).setFill()
    NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
    if let percent {
        let clamped = min(100, max(0, percent))
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * CGFloat(clamped) / 100, height: track.height)
        accent.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
```

Call `drawQuota()` after `drawFooter()`.

- [ ] **Step 5: Visual check**

Run the app and manually set quota:

```bash
.build/release/codex-light-mxp quota --five-hour 72 --weekly 48
.build/release/codex-light-mxp waiting
.build/release/CodexTrafficLightApp
```

Expected: red light remains dominant; quota rows are readable below `等你回复` without clipping.

## Task 5: App Polling and Menu Wiring

**Files:**
- Modify: `Sources/CodexTrafficLightApp/AppDelegate.swift`
- Modify: `Sources/CodexTrafficLightApp/StatusBarController.swift`

- [ ] **Step 1: Store current quota**

Add to `AppDelegate`:

```swift
private var currentQuota: QuotaSnapshot?
```

In startup and `pollState()`, assign:

```swift
currentQuota = snapshot.quota
```

- [ ] **Step 2: Pass quota into views**

Update `updateStatusOnly()`:

```swift
private func updateStatusOnly() {
    statusBar.apply(state: currentState, quota: currentQuota, muted: preferences.muted)
    floatingWindow.view.state = currentState
    floatingWindow.view.quota = currentQuota
}
```

Update `apply(state:playPrompt:source:)`:

```swift
statusBar.apply(state: state, quota: currentQuota, muted: preferences.muted)
floatingWindow.view.quota = currentQuota
floatingWindow.apply(state: state, show: shouldShowFloatingWindow(for: state, source: source))
```

- [ ] **Step 3: Update status bar signature**

Change:

```swift
func apply(state: LightState, muted: Bool)
```

to:

```swift
func apply(state: LightState, quota: QuotaSnapshot?, muted: Bool)
```

Set tooltip:

```swift
if let quota {
    item.button?.toolTip = "Codex 红绿灯：\(state.label) · 5小时 \(quota.fiveHourRemainingPercent)% · 1周 \(quota.weeklyRemainingPercent)%"
} else {
    item.button?.toolTip = "Codex 红绿灯：\(state.label)"
}
```

Add a menu line after current state:

```swift
if let quota {
    menu.addItem(withTitle: "额度：5小时 \(quota.fiveHourRemainingPercent)% · 1周 \(quota.weeklyRemainingPercent)%", action: nil, keyEquivalent: "")
} else {
    menu.addItem(withTitle: "额度：暂无数据", action: nil, keyEquivalent: "")
}
```

- [ ] **Step 4: Compile**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache SWIFTPM_CACHE_PATH=.build/swiftpm-cache swift build
```

Expected: build succeeds.

## Task 6: Quota Collector Strategy

**Files:**
- Create later if needed: `Sources/codex-light-quota-mxp/main.swift`
- Modify later if needed: `Package.swift`

First release should not include a background parser unless the quota payload contract is confirmed. Use this order:

1. Manual/CLI input: `codex-light-mxp quota --five-hour 72 --weekly 48`.
2. Optional helper after investigation: `codex-light-quota-mxp poll-once`.
3. Optional helper source: Codex app-server events such as `account/rateLimits/updated`, only if the event payload can be read through a stable local API or stable log shape.

If implementing the helper later, keep it separate from the App target:

```swift
let store = StateStore()
let quota = try QuotaProvider().readCurrentQuota()
try store.updateQuota(
    fiveHourPercent: quota.fiveHourRemainingPercent,
    weeklyPercent: quota.weeklyRemainingPercent,
    source: quota.source
)
```

This avoids giving the UI app responsibility for private Codex log parsing.

## Task 7: README and Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Document CLI**

Add:

```bash
codex-light-mxp quota --five-hour 72 --weekly 48
codex-light-mxp --json status
```

- [ ] **Step 2: Document JSON**

Add quota JSON under runtime state shape.

- [ ] **Step 3: Full verification**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=.build/clang-module-cache SWIFTPM_CACHE_PATH=.build/swiftpm-cache swift run codex-light-mxp-tests
./build.command
STATE=/tmp/codex-light-quota-state.json
CODEX_TRAFFIC_LIGHT_STATE_PATH="$STATE" .build/release/codex-light-mxp clear
CODEX_TRAFFIC_LIGHT_STATE_PATH="$STATE" .build/release/codex-light-mxp quota --five-hour 72 --weekly 48 --json
CODEX_TRAFFIC_LIGHT_STATE_PATH="$STATE" .build/release/codex-light-mxp waiting --json
```

Expected:

- Tests pass.
- Release build succeeds.
- JSON status includes quota and `aggregate_state` remains driven by task state.
- Floating UI shows quota rows and no text overlap.

## Open Decision

The UI/data model can be implemented now. Automatic quota collection should wait until we confirm the stable source for the 5-hour and weekly values. The observed `account/rateLimits/updated` event is promising, but this plan intentionally treats it as a later collector source rather than a hard dependency for the first UI feature.
