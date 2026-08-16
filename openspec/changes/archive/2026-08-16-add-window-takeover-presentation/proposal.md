# 提案：add-window-takeover-presentation

## Why

需求要求触发安全模式后原本 root 页面/正常流程不能执行。宿主在 didFinishLaunching 首行 start() 返回 true 后跳过全部启动任务（包括自身 window/root VC 构建）——此时界面上没有任何东西，present 方式（挂在宿主 key window rootVC 上）无处可挂。必须由库提供独立 UIWindow 接管显示：宿主跳过构建时此窗为唯一界面；宿主漏分流时形成覆盖兜底（双保险）。MPLaunch 类 APP 的 root 构建放在 Launchable 模块内，跳过编排后同样依赖此能力。

## What Changes

- 新增 `ALLaunchGuardSafeModeWindow`（UIKit，`#if canImport(UIKit)`）：创建独立 UIWindow（windowLevel 高于 .normal），rootViewController 为菜单式安全模式页，makeKeyAndVisible；优先绑定 foregroundActive 的 UIWindowScene，scene 未就绪时监听 `UIScene.willConnectNotification` 延迟挂载；均不可用时回退现有 present 路径。
- `ALLaunchGuardConfig` 新增 `presentationStyle` 枚举（`.dedicatedWindow`（默认）/ `.presentOnRoot`（旧行为））。
- `ALLaunchGuard` 新增 `public func activateSafeModeWindow()` 显式接管入口；`activateSafeMode()` 的 autoPresent 分流按 presentationStyle 走窗口接管或旧 present（后者 deprecated 回退）。
- 窗口生命周期：单例强持有防释放，安全模式激活期间不自动关闭（等待用户修复并手动重启）。

## Capabilities

### New Capabilities

- `safe-mode-window`：安全模式界面接管能力——独立 UIWindow 展示、scene 绑定与延迟挂载、展示样式配置、回退路径与窗口生命周期。

### Modified Capabilities

（无——crash-detection / fix-actions / safe-mode-ui 主 spec 需求不变，本变更是展示通道层。）

## Impact

- 新增 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`；修改 `Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`（+presentationStyle）、`Sources/ALLaunchGuard/ALLaunchGuard.swift`（activateSafeMode 分流 + activateSafeModeWindow）。
- 测试：presentationStyle 默认值与分流判定（非 UI 可测部分）；UIKit 分支 Xcode/xcodebuild iOS destination 构建验证；模拟器冒烟依赖 Change 5 的 Example App（本变更以编译验证 + 手动检查为主，Example 就绪后端到端复验）。
- 兼容：presentationStyle 默认 .dedicatedWindow 属行为变化（**BREAKING**，随 2.0.0，README 在 Change 5 说明）。
