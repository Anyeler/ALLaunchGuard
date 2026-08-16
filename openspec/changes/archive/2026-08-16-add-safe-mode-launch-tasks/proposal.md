# 提案：add-safe-mode-launch-tasks

## Why

安全模式下宿主跳过全部启动任务（含 MPLaunch onceUponAnApp），但仍有少数必要模块需要初始化（如日志上报 SDK）才能完成修复流程中的诊断与上报。当前宿主只能在安全模式分支手写初始化代码，范式不显式、各宿主重复且评审易遗漏。需要在库侧提供一个一等概念的最小任务钩子。硬约束：ALLaunchGuard 不依赖 MPLaunch——钩子为纯闭包类型，库内不出现任何 MPLaunch 符号；MPLaunch 宿主在自己的闭包内桥接（MPLaunch 侧的 runSafeModeTasks 属另一仓库的独立增量）。

## What Changes

- `ALLaunchGuard` 新增 `public var safeModeLaunchTasks: [() -> Void]`（默认空数组）与私有幂等门控 `didRunSafeModeLaunchTasks`。
- 执行点：`activateSafeMode()` 首行（先于 delegate 回调与窗口安装，保证最小模块在安全模式 UI 呈现前就绪），同步、按序、每个进程生命周期仅一次；覆盖阈值触发、粘滞触发、DEBUG 直进入三个路径。
- README「与启动编排器集成（MPLaunch 等）」专节补两段式范式：注册 safeModeLaunchTasks → 安全模式分支 return true；注明任务约束（自包含、轻量、不做磁盘 IO、禁止触碰 LaunchParams.inputs）。

## Capabilities

### New Capabilities

（无新能力域——属 crash-detection 能力扩展。）

### Modified Capabilities

- `crash-detection`：ADDED"安全模式最小启动任务"需求（钩子注册、执行时机与幂等、三触发路径覆盖、空注册无副作用）。

## Impact

- `Sources/ALLaunchGuard/ALLaunchGuard.swift`（属性 + 执行点）；`Tests/ALLaunchGuardTests/ALLaunchGuardTests.swift`（新增用例）；`README.md`（范式补充）。
- 依赖边界：Sources/ 内不得出现 MPLaunch/LaunchSession 符号（验证含 grep 自检）。
- 纯增量零破坏；默认空数组行为与 2.0 完全一致。
