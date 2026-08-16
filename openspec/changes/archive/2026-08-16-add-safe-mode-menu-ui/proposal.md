# 提案：add-safe-mode-menu-ui

## Why

需求要求安全模式页为可扩展菜单列表（点击某项才开始修复、完成后提示重启）。现有单按钮页面（ALLaunchGuardViewController，fixHandler + Fix 按钮）形态过时，且其按钮使用了 iOS 15+ API（UIButton.Configuration，L71-79）与 iOS 14 部署目标冲突——该文件从未经 iOS destination 编译验证，属现存隐患。Change 2 已建立 fixActions 协议与编排层，本变更提供菜单式 UI 消费层。

## What Changes

- 新增 `ALLaunchGuardSafeModeViewController`（UIKit，`#if canImport(UIKit)`）：头部沿用现有 icon/title/message 布局风格，下方 UITableView 菜单列表展示 `fixActions`（图标 + 标题 + 破坏性红色样式）；点击 cell → 执行态 spinner → 成功打勾置灰 / 失败红色可重试；底部常驻 `restartHint` 提示条（默认"修复完成后，请退出应用重新打开"）。全部使用 iOS 14 安全 API。
- `ALLaunchGuardConfig`：`fixButtonTitle` 字段移除（**BREAKING**），新增 `restartHint: String`；public init 参数同步调整（带默认值）。
- 旧 `ALLaunchGuardViewController` 标 `@available(iOS, deprecated, message:)` 完整保留为回退路径；顺带将其 iOS 15+ API（UIButton.Configuration）替换为 iOS 14 安全 API，修复现存隐患。
- 展示路径：本变更暂沿用现有 present 方式（`presentSafeModeUIIfNeeded` 语义扩展为可展示新菜单页——新 VC 为默认，旧 VC 可选），独立 UIWindow 接管属下一变更 add-window-takeover-presentation。

## Capabilities

### New Capabilities

- `safe-mode-ui`：安全模式菜单式修复页能力——动作列表展示、点击执行与状态反馈（执行中/成功/失败可重试）、重启提示、配置项（restartHint 等）、旧页面废弃与回退。

### Modified Capabilities

（无——crash-detection / fix-actions 主 spec 需求不变。）

## Impact

- 新增 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeViewController.swift`；修改 `Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`（fixButtonTitle → restartHint）、`Sources/ALLaunchGuard/ALLaunchGuardViewController.swift`（deprecated + iOS 14 API 修复）、`Sources/ALLaunchGuard/ALLaunchGuard.swift`（activateSafeMode 的 autoPresent 分支改展示新菜单页）。
- 测试：Config 字段测试更新（fixButtonTitle 断言迁移为 restartHint）；UIKit 分支需 Xcode MCP iOS destination 构建验证（swift test 不编译 UIKit 分支）。
- **BREAKING**：Config 的 fixButtonTitle 移除（唯一字段级破坏，随 2.0.0 发布，README 在 add-example-apps 中说明迁移）。
