# 设计：harden-thread-safety

## Context

现状（2.1 分支）：单例全部可变状态为裸 var，仅 Debug assert 主线程契约；shouldEnterSafeMode 文档承诺任意线程可读；预支写序 count 最先写；通知观察 queue: nil；install() 仅 assert 主线程。锁选型已确认 NSLock（负载为启动期个位数次微秒级临界区；读写锁的锁升级/写饥饿风险大于收益；Actor 破坏同步 start() 契约）。

## Goals / Non-Goals

**Goals:** 闭合真实竞争面（任意线程读 × 主线程写、Release 误调）；写序崩溃原子性偏向多计；通知/窗口主队列结构化；零公共签名变化、零行为回退。

**Non-Goals:** 读写锁/Actor；storage 实现内部加锁（UserDefaults cfprefsd 本身线程安全；自定义存储宿主自负）；perform 编排层改造（已主队列收口）。

## Decisions

### D1. 单锁 + 锁外回调纪律
`private let stateLock = NSLock()` + `@inline(__always) private func withStateLock<T>(_ body: () -> T) -> T`。锁内清单：
- `start()`：didStart 检查-置位原子化；裁决读取（safeModeActive/后台标记/uptime）；预支写序列（新写序）；generation/currentSessionMarkUptime 更新；阈值判定快照。
- `confirmLaunchSurvival`：generation/打点校验 + 两处 storage 写。
- `markLaunchSuccessful`/`reset()`：storage 写 + isInSafeMode 写（reset 的 delegate 退出回调在锁外）。
- `shouldEnterSafeMode`/`isInSafeMode` getter、crashThreshold/survivalTimeout/fixActions/safeModeLaunchTasks/uiConfig/delegate 存取器。
锁外清单（纪律红线）：activateSafeMode 的 delegate 回调、safeModeLaunchTasks 执行、窗口安装/present、perform 的 action.perform 与 completion 派发。模式：锁内算决策快照 → 解锁后执行副作用。start() 的"是否激活"决策在锁内得出，activateSafeMode() 在锁外调用（其 isInSafeMode 置位若已被锁内完成则无需重复——实施时把 isInSafeMode 置位纳入 start 锁内序列，activateSafeMode 只做回调与 UI）。
注意：start() 现有 Debug assert 保留；didStart 幂等语义不变。

### D2. 写序（崩溃原子性）
新序：`storage.lastLaunchDiedInBackground = false` → `storage.lastLaunchMarkUptime = markUptime` → `storage.consecutiveCrashCount = count`。推演：任意相邻两次写之间死亡——①标记已清、打点未写：次启按"无打点"处理，旧计数保留 +1（多计，安全）；②打点已写、count 未写：次启读到新打点与旧计数，正常 +1（正确）。对比旧序（count 先写）在"count 已写、标记未清"死亡时次启会因残留标记清零 → 漏检。注释写明取舍依据。

### D3. 通知 queue: .main
registerLifecycleObservers 两处 addObserver 的 queue 参数 nil → .main。UIKit 生命周期通知本就主线程发帖，行为不变、契约结构化；回调与锁路径同队列，无新竞争。

### D4. install 自 hop
```swift
func install(rootViewController: UIViewController) {
    if !Thread.isMainThread {
        DispatchQueue.main.async { self.install(rootViewController: rootViewController) }
        return
    }
    assert(Thread.isMainThread, ...)  // 既有哨兵保留
    ...
}
```
Release 下后台误调从"UIKit 状态竞争"收敛为"一帧延迟"。幂等门控不变。

### D5. 测试策略
- hammer：DispatchQueue.concurrentPerform 8 路读 shouldEnterSafeMode/isInSafeMode，同时主线程外串行 start(新实例+MockStorage)/reset 循环若干次，断言不崩不死锁（用 XCTestExpectation + 超时保护）。
- 写序推演：MockStorage 预置"新打点 + 旧计数 + 后台标记 false"残留态 → 新实例 start → 断言计数 = 旧值+1（未被误清）。
- 死锁回归：MockDelegate 在 launchGuardDidEnterSafeMode 内读 shouldEnterSafeMode，阈值触发路径断言正常返回。
- 既有 62 测试全量回归（锁改造不改语义）。

## Risks / Trade-offs

- [锁内误触外部代码 → 死锁] → D1 锁外清单纪律 + 评审走查 + hammer 测试超时保护。
- [start() 锁化后与存活计时闭包（主队列）嵌套] → 计时闭包在主队列执行 confirm，走锁正常（无递归锁需求，调用栈不重入）。
- [写序变化改变极端场景判定] → 偏向多计有 reset 出口；README 已知限制补充。
- [性能] → 启动期个位数次微秒级临界区，不可测量。

## Migration Plan

实现 → swift test（62 + 新增）+ iOS 构建 → 归档。内部改造无迁移。

## Open Questions

（无。）
