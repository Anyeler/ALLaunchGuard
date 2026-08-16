# 设计：add-survival-based-crash-detection

## Context

当前 `ALLaunchGuard.start()`（ALLaunchGuard.swift L73-93）为"无条件计数 +1 → 阈值激活 → willTerminate 重置"，L84-92 的通知监听使用字符串 shim 通知名（L131），非 UIKit 平台可编译但 iOS 上几乎不回调；计数清零完全依赖宿主调用 `markLaunchSuccessful()`。存储协议（ALLaunchGuardStorage.swift L4-7）仅一个 Int 属性。测试体系为 MockStorage + MockDelegate 注入（ALLaunchGuardTests.swift L6-23），12 个测试可 `swift test` 运行。约束：Swift 5 / iOS 14+；UIKit 隔离（`#if canImport(UIKit)`）；测试必须可在 macOS `swift test` 下运行（UIKit 分支不参与编译）。

## Goals / Non-Goals

**Goals:**
- 判定语义升级为"预支计数 + 5 秒存活确认 + 后台死亡/设备重启不计 + 粘滞安全模式"（详见 specs/crash-detection/spec.md，状态机为规范来源）。
- 判定核心纯 Foundation、可注入调度、可在 macOS/Linux 单测。
- 公共 API 零删除零签名破坏；存储协议新增需求对第三方实现零破坏。

**Non-Goals:**
- 安全模式 UI 改造、修复动作协议、窗口接管（属后续变更 add-fix-action-protocol / add-safe-mode-menu-ui / add-window-takeover-presentation）。
- 崩溃信号捕获、Codable 结构化记录 v2 存储、premain 介入（已否决/演进项）。
- README/版本收口（属 add-example-apps 变更）。

## Decisions

### D1. 预支计数（保留）而非"下次启动结算时间戳"
业界两种主流形态：GYBootingProtection 预支计数 + N 秒清零；Sam 方案"残留时间戳即闪退"下次结算。选择预支计数：与现有 12 个测试及用户预期（第 3 次崩溃启动当场触发）完全一致，改动面最小；"未满 5 秒死亡计数保留"由"计时闭包无机会执行"天然成立，无需额外结算逻辑。

### D2. 存活确认：main queue asyncAfter + generation 防误清
计时闭包经 internal `survivalScheduler: (@escaping () -> Void) -> Void` 注入（默认 `DispatchQueue.main.asyncAfter(deadline: .now() + survivalTimeout)`）。主线程 hang ⇒ 确认永不发生 ⇒ 看门狗语义正确。闭包捕获启动时的自增 generation（Int），触发时仅当 generation 与当前会话一致才清零——防跨会话竞态误清（单进程内 start() 幂等，generation 主要防测试与极端重入）。`markLaunchSuccessful()` 保留为提前确认入口，与定时器幂等共存（内部走同一确认函数）。

### D3. 后台死亡防护：didEnterBackground 持久化标记
进入后台时置 `lastLaunchDiedInBackground = true`；下次 start() 裁决发现该标记 → 清零计数（再预支递增）。didEnterBackground 在 iOS 可靠回调（与 willTerminate 不同），覆盖系统回收/上滑强杀后台/OOM。非 UIKit 平台通知名沿用 shim 模式（didEnterBackground / willTerminate 两个 shim），真实 UIKit 下用 `UIApplication.didEnterBackgroundNotification` 等（#if canImport(UIKit) 选择通知名，替换现有单一字符串 shim）。标记写入后进程继续存活超过 5 秒：存活确认仍会清零计数与标记，语义一致（未死即正常）。

### D4. 设备重启防护：systemUptime 单调反转
start() 写 `lastLaunchMarkUptime = ProcessInfo.processInfo.systemUptime`；下次裁决若存储值 > 当前 uptime ⇒ 中间发生重启 ⇒ 清零。systemUptime 每次开机归零、不受改时间/NTP 影响，优于 wall clock。默认 no-op 存储实现返回 nil ⇒ 不触发重启防护（降级语义）。

### D5. 粘滞安全模式 + 防绕过
计数达阈值时持久化 `safeModeActive = true`。后续启动 start() 裁决发现粘滞标记 ⇒ 不递增计数、不启动存活计时器、直接激活安全模式返回 true——否则安全模式页挂 5 秒计数清零、杀进程重启即绕过。`reset()` 清零计数 + 清粘滞标记（唯一退出路径）。`shouldEnterSafeMode` 计算属性 = `storage.safeModeActive || storage.consecutiveCrashCount >= crashThreshold`，纯读。

### D6. 存储协议扩展默认 no-op（而非 v2 重写）
协议新增三个 `var ... { get set }` 需求，protocol extension 提供默认实现（get 返回 nil/false、set 忽略）。第三方实现零改动；UserDefaults 实现新增三个独立 key 完整持久化。备选（结构化 Codable 记录 + loadRecord/save 契约）被否决：对本库规模过度设计，且破坏所有第三方实现。

### D7. UIKit 通知隔离方式
通知名在 `#if canImport(UIKit)` 下用真实 `Notification.Name`（UIApplication.didEnterBackgroundNotification / willTerminateNotification），非 UIKit 下用字符串 shim——沿用现有 L131 模式扩展为两个 shim 常量，保持 Linux swift test 可编译。观察者注册在 start() 内完成（非 UIKit 平台仍注册 shim 名，行为为永不触发，测试通过直接调用 internal 方法模拟）。

### D8. 调试入口与测试注入均为最小面
`enterSafeModeForTesting()` 仅 `#if DEBUG`；`survivalScheduler` 为 internal var，`@testable` 访问。不引入 Clock 协议抽象（重启检测直接读 ProcessInfo，测试通过预置存储值覆盖）。

## Risks / Trade-offs

- [前台 5 秒内上滑强杀计为闪退] → 业界唯一无法根除项；阈值 3 连发兜底；survivalTimeout/crashThreshold 可调；README 明示（后续变更）。
- [didEnterBackground 触发后进程仍活过 5 秒又正常使用] → 存活确认会同时清零计数与标记，无双计；测试覆盖。
- [UserDefaults 写入在 cfprefsd 落盘前断电丢失] → 丢证据方向为"漏判"而非"误判"，可接受；FileStorage 列演进项。
- [行为变化：不再调用 markLaunchSuccessful 的宿主计数也会 5 秒自动清零] → 属语义增强，proposal 已声明 BREAKING，随 2.0.0 发布并 README 说明。
- [旧计数残留（1.0.0 升级）] → 打点法下存活 5 秒自动清除，最坏首启触发一次安全模式可接受。

## Migration Plan

1. 实现 + 测试全绿后合入（OpenSpec apply → archive）。
2. 版本随后续 add-example-apps 变更统一升至 2.0.0；无数据迁移（旧 key 语义不变，新增字段缺失时走默认值）。
3. 回滚：revert 提交即可，旧计数 key 未被破坏。

## Open Questions

（无——已在方案综合阶段定案。）
