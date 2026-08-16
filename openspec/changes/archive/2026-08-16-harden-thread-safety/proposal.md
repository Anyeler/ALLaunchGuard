# 提案：harden-thread-safety

## Why

并发审计确认两处真实问题：① `shouldEnterSafeMode` 文档承诺任意线程可读（ALLaunchGuard.swift L41-43），与主线程写路径（start/reset/配置赋值）构成混合访问面，且 Release 下宿主违反契约的后台误调仅有 Debug assert 防线；② 预支写序缺陷——count 最先写（L185-189），两次 storage set 之间进程被杀会把本次闪退误清零（漏检崩溃循环）。用户要求评估并适当使用锁（已确认 NSLock，不用读写锁/Actor）。

## What Changes

- 单例核心状态加一把私有 NSLock（`stateLock` + `withStateLock`）：锁内仅自身可变状态与 storage 读写（start 的 didStart 检查-置位原子化与存储裁决序列、confirmLaunchSurvival、markLaunchSuccessful、reset、shouldEnterSafeMode、isInSafeMode/crashThreshold/survivalTimeout/fixActions/safeModeLaunchTasks/uiConfig/delegate 存取）；delegate 回调、UI 安装、最小任务执行、completion 一律锁外（防重入死锁）。公共签名零变化。
- 预支写序修复：`lastLaunchDiedInBackground = false` → `lastLaunchMarkUptime` → 最后 `consecutiveCrashCount = count`（中途被杀偏向多计触发安全模式——用户有 reset 出口，优于漏检崩溃循环）。
- 生命周期通知观察者 `queue: nil` → `queue: .main`（registerLifecycleObservers 两处），隐式主线程契约升级为结构保证。
- 窗口协调器 `install()` 自 hop 主队列（主线程直接执行/否则 dispatch main 后 return，对齐 activateSafeModeWindow 既有模式），assert 保留作 Debug 哨兵。
- README 线程契约章节更新：读路径（shouldEnterSafeMode/isInSafeMode）任意线程安全；写路径（start/reset/markLaunchSuccessful/fixActions/safeModeLaunchTasks 赋值）主线程；perform 编排主队列收口；自定义 Storage 线程安全宿主自负。
- 测试：concurrentPerform 多线程 hammer 读路径 + 后台 start/reset 不死锁不崩；写序崩溃原子性推演用例（模拟"uptime 已写、count 未写"的残留状态 → 次启判定偏向保留计数）。

## Capabilities

### New Capabilities

（无新能力域。）

### Modified Capabilities

- `crash-detection`：ADDED"并发安全"需求（状态访问串行化契约、任意线程读安全、写序崩溃原子性偏向多计）。

## Impact

- `Sources/ALLaunchGuard/ALLaunchGuard.swift`（锁改造 + 写序）、`Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`（install hop）、`Tests/`（并发用例）、`README.md`。
- 纯内部改造，公共 API 签名与行为语义不变（除写序偏向多计的判定边界微调，README 已知限制说明）。
