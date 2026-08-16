# 提案：fix-pr3-review-comments

## Why

PR #3 的 Copilot 评审指出两处并发加固引入的真实缺陷：① `start()` 的 `didStart` 检查与置位分裂在两个独立的 `withStateLock` 临界区（ALLaunchGuard.swift L241 检查、后续锁段置位），Release 并发下第二个线程可能在置位前通过 guard，导致重复注册观察者/重复写存储，破坏幂等语义——与 harden-thread-safety 设计声称的"check-and-set 原子化"不符；② `isInSafeMode` 在锁改造中从 `public private(set)` 变为带公开 setter 的 `public var`，扩大公共 API 面且允许外部篡改安全模式状态，与"签名零变化"承诺矛盾。

## What Changes

- `start()`：将 didStart 检查-置位合并为单次加锁的原子 check-and-set（guard 失败路径返回当前 isInSafeMode 快照），移除后续锁段内冗余的 `didStart = true`。
- `isInSafeMode`：移除公开 setter，恢复对外只读（get 仍走锁，内部经 `_isInSafeMode` 更新），公共 API 面回到 2.0 形态。
- 补充回归测试：并发 start 幂等（多线程竞态下观察者仅注册一次/计数仅预支一次的断言或结构验证）；isInSafeMode 编译期只读性由 API 形态保证（辅以注释说明）。

## Capabilities

（skip_specs：实现缺陷修复，无 spec 级行为变化——并发安全需求本就要求状态访问串行化与 API 面稳定。）

## Impact

- `Sources/ALLaunchGuard/ALLaunchGuard.swift`；`Tests/ALLaunchGuardTests/ALLaunchGuardTests.swift`。
- 验证：swift test 全绿 + TSan + iOS 构建 0 警告；推送至 PR #3 分支并回复评审意见。
