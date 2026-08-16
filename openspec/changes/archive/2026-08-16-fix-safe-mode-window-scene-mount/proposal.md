# 提案：fix-safe-mode-window-scene-mount

## Why

Example 冒烟暴露 add-window-takeover-presentation 的两处缺陷：① SceneDelegate 生命周期下安全模式窗口黑屏——`activateSafeModeWindow()` 经 `DispatchQueue.main.async` 派发使 install 晚于 `willConnectNotification`（观察者注册错过通知），且 scene 候选过滤仅接受 `.foregroundActive` 而回调/早期时 scene 常为 `foregroundInactive`，最终 5 秒超时降级的 frame window 在 scene App 上不可见；② 经典 AppDelegate 生命周期下 scene 永不连接，窗口要等满 5 秒超时才降级创建，期间黑屏。

## What Changes

- install 挂载时机：已在主线程时同步执行（不等 main.async），确保 willConnect 观察者在通知发出前注册。
- scene 候选放宽：优先 foregroundActive；无则接受任意 UIWindowScene（foregroundInactive/unattached，scene 激活后窗口自然可见）。
- 经典 delegate 立即降级：应用未配置 scene manifest（Bundle.main 无 UIApplicationSceneManifest）时跳过等待，立即以全屏 frame 创建窗口；配置了 scene manifest 才走等待 + 超时路径。
- 新增测试：分流/降级判定纯函数（scene manifest 检测抽象可注入）单测；既有 46 测试回归。

## Capabilities

### New Capabilities

（无。）

### Modified Capabilities

- `safe-mode-window`：Scene 绑定与延迟挂载策略修正（接受非激活 scene、同步注册时机、无 scene manifest 立即降级），消除 SceneDelegate 黑屏与经典路径 5 秒黑屏。

## Impact

- 修改 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`（挂载策略）、`Sources/ALLaunchGuard/ALLaunchGuard.swift`（activateSafeModeWindow 派发方式）；测试补充。
- 两处 Example 冒烟复验（尤其 MPLaunchExample 的 scene 路径）。
