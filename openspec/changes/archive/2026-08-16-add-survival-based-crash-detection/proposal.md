# 提案：add-survival-based-crash-detection

## Why

当前 ALLaunchGuard 采用"每次启动无条件计数 +1，依赖宿主调用 markLaunchSuccessful() 清零、监听 willTerminate 重置"的判定方式，存在两类缺陷：iOS 上 willTerminate 通知几乎不会回调（上滑强杀、系统回收均无回调），宿主忘记调用 markLaunchSuccessful() 时正常启动也会累计误判；且无时间维度，无法表达需求要求的"每次进程存活不超过 5 秒视为一次启动闪退"。业界主流方案（微信读书 GYBootingProtection 计时器法、天猫安全模式 flag 打点法）均以"存活时间确认 + 多条件清零"为核心，误判率显著更低。

## What Changes

- 判定算法重构为「预支计数 + 存活确认 + 双重误判防护」：
  - `start()` 时预支递增计数，并写入本次启动的 systemUptime 打点；
  - 启动 5 秒（可配 `survivalTimeout`）存活计时到期后自动清零计数（不再强依赖宿主手动调用）；
  - 上次启动若已进入后台（didEnterBackground 持久化标记），下次启动不计为闪退（系统回收/上滑强杀后台/OOM 不计）；
  - 上次打点 uptime 大于本次 systemUptime（设备重启）时清零计数；
  - 安全模式启动不递增计数、不启动存活计时器（防绕过），`safeModeActive` 粘滞持久化，仅 `reset()` 可退出。
- `start()` 返回值变为 `@discardableResult -> Bool`（是否进入安全模式），源码兼容；新增只读计算属性 `shouldEnterSafeMode`（可在 start() 之前无副作用调用）。
- 存储协议 `ALLaunchGuardStorage` 新增三个可读写需求（`lastLaunchMarkUptime` / `lastLaunchDiedInBackground` / `safeModeActive`），均提供 protocol extension 默认 no-op 实现，第三方实现零改动（降级为纯计数模式）。
- 新增 `#if DEBUG` 调试入口 `enterSafeModeForTesting()`（强制进入安全模式，用于测试与后续 Example 演示）。
- 新增 internal 调度器注入（`survivalScheduler`），使 5 秒计时可在单元测试中注入立即执行/no-op，不进公共 API。
- 用真实 UIKit 通知名（didEnterBackground / willTerminate）替换现有字符串 shim，保持 `#if canImport(UIKit)` 隔离。
- 行为变化（**BREAKING**，将在 README 与后续变更中声明、随 2.0.0 发布）：不调用 markLaunchSuccessful() 的宿主其计数也会在存活 5 秒后自动清零；"连续启动崩溃"的判定窗口收窄为"5 秒内短命启动"。

## Capabilities

### New Capabilities

- `crash-detection`：启动闪退判定能力——存活时间打点、预支计数、多条件清零（存活确认/后台死亡/设备重启/正常退出）、阈值触发安全模式、粘滞安全模式状态与极早期查询。

### Modified Capabilities

（无——openspec/specs 目前为空，本变更为首份 spec。）

## Impact

- 源码：`Sources/ALLaunchGuard/ALLaunchGuard.swift`（start() 状态机重写、新属性与查询、通知观察者）、`Sources/ALLaunchGuard/ALLaunchGuardStorage.swift`（协议扩展 + UserDefaults 实现新字段）。
- 测试：`Tests/ALLaunchGuardTests/ALLaunchGuardTests.swift`（现有 12 个测试语义迁移 + 新增判定场景测试，注入调度器与 MockStorage）。
- API 兼容性：公共 API 零删除、零签名破坏（start() 返回值为新增 discardable 结果）；存储协议新增需求带默认实现，对第三方实现向后兼容。
- 不涉及 UI（安全模式页面改造属后续变更）。
