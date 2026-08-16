# 任务：add-safe-mode-launch-tasks

## 1. 实现（TDD：先写失败测试）

- [x] 1.1 `Tests/ALLaunchGuardTests/ALLaunchGuardTests.swift` 新增用例：注册两个任务在阈值触发时按序执行一次且先于 delegate 回调（用执行顺序数组断言）；粘滞路径（storage.safeModeActive=true 直接 start）也执行；DEBUG 入口路径执行；同进程二次激活不重复执行；未注册无副作用
- [x] 1.2 `Sources/ALLaunchGuard/ALLaunchGuard.swift`：新增 `public var safeModeLaunchTasks: [() -> Void] = []`（紧邻 fixActions，带文档注释：自包含/轻量/禁止磁盘 IO/禁止触碰启动编排器内部状态）与 `private var didRunSafeModeLaunchTasks = false`；`activateSafeMode()` 中 isInSafeMode 置位后、delegate 前执行（guard 门控 + 按序 forEach）
- [x] 1.3 依赖边界自检：`grep -r "MPLaunch\|LaunchSession" Sources/` 零命中

## 2. 文档与验证

- [x] 2.1 README「与启动编排器集成（MPLaunch 等）」专节补两段式范式代码（注册 safeModeLaunchTasks → start() 门控 return）+ 任务约束说明（自包含、轻量同步、不做磁盘 IO；MPLaunch 宿主可在闭包内桥接依赖图执行，禁止触碰 LaunchParams.inputs）
- [x] 2.2 swift test 全绿（存量 + 新增）；swift build 0 新增警告；xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'（独立 derivedDataPath）0 错误 0 警告
- [x] 2.3 tasks 勾选完成，openspec validate 通过
