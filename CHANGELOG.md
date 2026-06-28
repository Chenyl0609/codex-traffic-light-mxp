# Changelog

## 2026-06-29 — Claude Code 适配与 UI 优化

### 品牌重命名

- 浮窗标题从 "Codex" 改为 "Claude"
- 菜单栏 tooltip 从 "Codex 红绿灯" 改为 "Cloud Code 红绿灯"
- 状态消息从 "Codex traffic light" 改为 "Cloud Code light"
- README 全文更新为 Cloud Code Light

### .app 包支持

- 新增 `create-app-bundle.sh`：构建并打包成 macOS .app，安装到 ~/Applications
- 新增 `install.command`：一键安装脚本（构建 + 打包 + CLI 链接 + 配置 hooks）
- App 名称：CloudCodeLight，支持从 Launchpad / Spotlight / Finder 启动

### Claude Code Hooks 配置

- 新增 `Docs/hooks-claude-code.example.json`：Claude Code hooks 配置示例
- `install.command` 自动将 hooks 合并到 `~/.claude/settings.json`
- 修正 hooks 格式为 Claude Code 规范（matcher + hooks 嵌套结构）
- 支持事件：UserPromptSubmit、PreToolUse、Notification、Stop、SubagentStop

### UI 优化

- 窗口尺寸从 116x340 缩小到 75x220（约 65%）
- 字体按比例缩小：标题 15→10pt，状态文字 14→9pt
- 灯泡、光晕、高光等元素按比例缩放
- 移除额度显示（5小时 / 1周），界面更紧凑
- 菜单栏移除额度信息，tooltip 只显示状态

### 灯光效果优化

- 不亮灯时：光晕完全透明（alpha 0.0），无任何光晕
- 亮灯时：光晕 alpha 0.35，清晰可见
- 光晕半径 28，不超出窗口边界
- 三盏灯间距均匀调整

### 交互改进

- **单击浮窗**：取消提示音 + 停止闪烁 + 隐藏浮窗 + 弹出 VS Code
- **双击浮窗**：同单击（统一行为）
- **Claude 开始工作时**：浮窗自动弹出显示
- **VS Code 不在前台时**：每 2 秒检测，自动弹出浮窗提醒

### Bug 修复

- 修复 `looksWaiting` 误判：移除 `?` 和 `？` 匹配，避免 Claude 正常回复被误判为红灯
- 修复 Swift 6 并发安全：Timer 闭包中使用 `DispatchQueue.main.async` 访问 main actor 属性
- 修复 hooks 配置格式错误（Expected array, but received undefined）
- VS Code 唤起改用 `open -a "Visual Studio Code"`，兼容无 URL scheme 注册的情况

### 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Sources/CodexTrafficLightApp/TrafficLightView.swift` | 修改 | 标题改为 Claude，移除额度绘制，缩小尺寸，优化灯光效果，添加单击/双击回调 |
| `Sources/CodexTrafficLightApp/AppDelegate.swift` | 修改 | 点击处理、VS Code 唤起、浮窗自动显示、VS Code 前台检测 |
| `Sources/CodexTrafficLightApp/FloatingLightWindow.swift` | 修改 | 添加 onDismiss 回调、show() 方法 |
| `Sources/CodexTrafficLightApp/StatusBarController.swift` | 修改 | 移除额度菜单和 tooltip 额度信息 |
| `Sources/CodexTrafficLightCore/TrafficLightLayout.swift` | 修改 | 窗口缩小、移除额度布局、调整灯间距 |
| `Sources/CodexTrafficLightCore/HookMapper.swift` | 修改 | 移除 ? 误判 |
| `Sources/CodexTrafficLightCore/HookBridge.swift` | 修改 | 状态消息重命名 |
| `Sources/codex-light-mxp/main.swift` | 修改 | 状态消息重命名 |
| `README.md` | 修改 | 全文更新为 Cloud Code Light 文档 |
| `Docs/hooks-claude-code.example.json` | 新增 | Claude Code hooks 配置示例 |
| `create-app-bundle.sh` | 新增 | .app 打包脚本 |
| `install.command` | 新增 | 一键安装脚本 | 
