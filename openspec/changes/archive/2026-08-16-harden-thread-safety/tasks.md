# 任务：harden-thread-safety

## 1. 锁改造（TDD：先写失败/回归测试）

- [x] 1.1 新增并发测试（ALLaunchGuardTests.swift）：concurrentPerform 8 路读 shouldEnterSafeMode/isInSafeMode + 并发 start/reset（独立实例 + MockStorage）不崩不死锁（Expectation 超时保护）；写序残留态推演用例（新打点 + 旧计数 + 标记 false → start 后计数 = 旧值+1）；delegate 回调内读 shouldEnterSafeMode 不死锁用例
- [x] 1.2 `Sources/ALLaunchGuard/ALLaunchGuard.swift`：新增 stateLock + withStateLock；按 design D1 锁内清单改造 start（didStart 原子化 + 裁决 + 新写序 + isInSafeMode 置位纳入锁内）/confirmLaunchSurvival/markLaunchSuccessful/reset/shouldEnterSafeMode/各属性存取器；锁外执行 delegate/safeModeLaunchTasks/UI/completion；保留 Debug assert
- [x] 1.3 写序调整（design D2）：预支序列改为 标记清零 → 打点 → count 最后；注释写明崩溃原子性偏向多计的取舍

## 2. 主队列结构化

- [x] 2.1 registerLifecycleObservers 两处 queue: nil → queue: .main
- [x] 2.2 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`：install() 自 hop 主队列（design D4），assert 哨兵保留，幂等门控不变

## 3. 文档与验证

- [x] 3.1 README 线程契约章节更新：读路径任意线程安全、写路径主线程、perform 主队列收口、自定义 Storage 宿主自负；已知限制补写序偏向多计说明
- [x] 3.2 swift test 全绿（62 存量 + 新增）；swift build 0 新增警告；xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'（独立 derivedDataPath）0 错误 0 警告；可选 swift test -sanitize=thread 抽查
- [x] 3.3 openspec validate 通过，tasks 勾选完成
