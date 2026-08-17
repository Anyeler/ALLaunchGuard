# 提案：add-basic-example-safe-mode-tasks-demo

## Why

BasicExample（通用示例，不依赖 MPLaunch）已演示门控范式、fixActions 与崩溃循环闭环，但未注册 safeModeLaunchTasks——与 MPLaunchExample（其安全模式分支经 safeModeLaunchTasks 桥接 LaunchSession.runSafeModeTasks）不对齐，导致通用宿主的最小任务接入形态缺少可运行参考。README safeModeLaunchTasks 章节的官方示例语义（日志模块最小初始化）也缺乏落地示例。

## What Changes

- BasicExample 新增纯 Foundation 内存级模拟日志模块 `DemoSafeModeLogger`（独立文件，"一概念一文件"示例惯例）：幂等初始化 + 记录安全模式启动事件，两任务展示注册顺序与任务依赖语义。
- AppDelegate 在 fixActions 之后、start() 之前注册 `safeModeLaunchTasks = [{ bootstrap }, { log }]`，编号注释与 MPLaunchExample 形态对齐。
- 可见性闭环：最小任务写入一次性 UserDefaults 演示标记（示例演示豁免，注释说明生产任务遵守无磁盘 IO 约束），修复重启回正常路径后首页展示一次性横幅"上次安全模式启动：最小任务已执行"，读后清零。
- pbxproj 四处登记新文件（仿 ClearDemoDataAction.swift 条目模式）。
- README：Examples 章节 BasicExample 能力清单追加；safeModeLaunchTasks 章节补两个 Example 互为对照的指引。
- 库源码零改动（safeModeLaunchTasks 钩子 2.1 已就绪），65 测试基线不动，podspec 不收口版本。

## Capabilities

### New Capabilities

（无新能力域。）

### Modified Capabilities

- `example-apps`：MODIFIED"通用示例 App"需求——追加 safeModeLaunchTasks 最小任务演示与一次性横幅闭环（保留原 Requirement 名与既有 Scenario 名，追加新场景）。

## Impact

- `Examples/BasicExample/`：AppDelegate.swift、HomeViewController.swift、新增 SafeModeLogBuffer.swift、project.pbxproj。
- `README.md`：两处小节补充。
- 不触碰 Sources/、Tests/、podspec、Package.swift。
