# 任务：add-survival-based-crash-detection

## 1. 存储协议扩展

- [x] 1.1 修改 `Sources/ALLaunchGuard/ALLaunchGuardStorage.swift`：协议新增三个可读写需求（lastLaunchMarkUptime: TimeInterval? / lastLaunchDiedInBackground: Bool / safeModeActive: Bool），并提供 protocol extension 默认实现（get 返回 nil/false，set 忽略）
- [x] 1.2 `UserDefaultsLaunchGuardStorage` 新增三个独立 key（ALLaunchGuard.lastLaunchMarkUptime / .lastLaunchDiedInBackground / .safeModeActive）完整持久化（Double/Bool 读写）
- [x] 1.3 单测：仅实现旧协议的存储实现（不实现新需求）可编译且降级为纯计数模式；UserDefaults 实现新字段读写往返

## 2. 判定核心状态机（TDD：先写失败测试再实现）

- [x] 2.1 在 `Tests/ALLaunchGuardTests/` 中先新增判定场景测试（注入 survivalScheduler：立即执行/no-op 两种 fake；复用 MockStorage 并扩展内存实现三个新字段）：3 次短命启动第 3 次触发；存活确认清零；no-op 计数保留；后台死亡标记次启不计数；uptime 反转（重启）不计数；安全模式启动计数不变不被清；generation 防误清；shouldEnterSafeMode 纯读无副作用；markLaunchSuccessful 与自动清零幂等共存
- [x] 2.2 重写 `Sources/ALLaunchGuard/ALLaunchGuard.swift` 的 `start()` 为状态机（@discardableResult 返回 Bool）：裁决残留状态（safeModeActive 粘滞 → 直接激活不递增不计时；lastLaunchDiedInBackground → 清零；lastLaunchMarkUptime > 当前 systemUptime → 清零）→ 预支递增 + 写 markUptime + 清后台标记 → 阈值激活并持久化 safeModeActive → 未触发则启动 survivalTimeout 存活计时（generation 匹配才清零）
- [x] 2.3 新增 `public var survivalTimeout: TimeInterval = 5`、internal `survivalScheduler` 注入、`public var shouldEnterSafeMode: Bool` 计算属性、`#if DEBUG` 的 `enterSafeModeForTesting()`（激活安全模式并持久化粘滞标记）
- [x] 2.4 `reset()` 扩展为清零计数 + 清除 safeModeActive 粘滞标记 + 触发退出回调；`markLaunchSuccessful()` 内部走统一确认函数（清计数 + 清后台标记）
- [x] 2.5 通知观察者升级：`#if canImport(UIKit)` 下使用真实 `UIApplication.didEnterBackgroundNotification` / `willTerminateNotification`（didEnterBackground → 持久化后台标记；willTerminate → 清零），非 UIKit 下保留字符串 shim 常量（两个），测试通过 internal 方法直接模拟回调
- [x] 2.6 迁移现有 12 个测试的语义（如 needed）：保持回归底线全绿（注：testStartIsIdempotent 等计数断言在 no-op 调度下不变）

## 3. 验证与收口

- [x] 3.1 运行 `swift test` 全绿（新旧测试合计约 20+ 个），输出测试摘要
- [x] 3.2 运行 `swift build` 无警告新增；确认公共 API 无删除、无签名破坏（start() 返回值为 discardable 新增）
- [x] 3.3 检查 UIKit 分支代码（新通知观察者部分）无 iOS 15+ API（本变更不改 UI，仅通知注册）
