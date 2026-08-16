# 任务：fix-pr3-review-comments

- [x] 1.1 `Sources/ALLaunchGuard/ALLaunchGuard.swift` start()：把 `guard withStateLock({ !didStart })` 与后续锁段内的 `didStart = true` 合并为单次加锁的原子 check-and-set（锁内 `guard !didStart else { return 快照 }` + 立即置位 + 继续裁决序列整体同锁），guard 失败时返回当前 isInSafeMode 锁内快照；确保通知注册仍在锁外、仅执行一次
- [x] 1.2 `isInSafeMode` 移除公开 setter：保留 `get { withStateLock { _isInSafeMode } }`，删除 `set`，对外恢复只读语义（等价 public private(set)），注释注明内部更新路径
- [x] 1.3 测试：新增/调整并发 start 幂等用例（DispatchQueue.concurrentPerform 多路并发 start 同一实例，断言计数仅预支一次或结构一致性）；确认既有 hammer 用例仍绿；检查测试代码中若有对 isInSafeMode 赋值的写法并改为经合法路径（reset/enterSafeModeForTesting）
- [x] 1.4 验证：swift test 全绿；swift test --sanitize=thread 无告警；swift build 0 警告；xcodebuild iOS Simulator 0 错误 0 警告
- [x] 1.5 归档本变更；提交并推送至 feat/2.1-safe-mode-tasks-and-actions；回复 PR #3 两条评审意见
