# 任务：add-basic-example-safe-mode-tasks-demo

## 1. 示例代码

- [x] 1.1 新建 `Examples/BasicExample/BasicExample/SafeModeLogBuffer.swift`：DemoSafeModeLogger 单例（shared/buffer/bootstrapped；static bootstrap() 幂等初始化 + print 任务 1 日志；static log(_:) append + print 任务 2 日志）；类注释写明任务约束四要点（自包含/轻量同步/无磁盘 IO/不触碰编排器）、与 MPLaunchExample 桥接形态的对照、"宿主侧演示代码，库只按序执行闭包"
- [x] 1.2 `Examples/BasicExample/BasicExample/AppDelegate.swift`：fixActions 之后、start() 之前插入 safeModeLaunchTasks 注册（两任务闭包）；注册闭包内追加一次性 UserDefaults 演示标记写入（key `BasicExample.safeModeMinimalTaskRan`，注释注明示例演示豁免）；编号注释与 MPLaunchExample 对齐、后续编号顺延
- [x] 1.3 `Examples/BasicExample/BasicExample/HomeViewController.swift`：viewDidLoad 读取演示标记，为 true 时展示一次性横幅"上次安全模式启动：最小任务已执行（示例）"，读后清零
- [x] 1.4 `Examples/BasicExample/BasicExample.xcodeproj/project.pbxproj`：新文件四处登记（PBXBuildFile / PBXFileReference / group children / Sources phase），仿 ClearDemoDataAction.swift 条目模式，新 ID grep 确认唯一

## 2. 文档

- [x] 2.1 README Examples 章节 BasicExample 能力清单追加"注册 safeModeLaunchTasks 最小任务演示（模拟日志初始化 + 一次性横幅闭环）"
- [x] 2.2 README safeModeLaunchTasks 章节末尾补一句：完整可运行示例见 Examples/BasicExample（纯 Foundation）与 Examples/MPLaunchExample（编排器桥接）互为对照

## 3. 验证与归档

- [x] 3.1 swift build + swift test（库零改动，65 测试全绿基线）
- [x] 3.2 xcodebuild -project Examples/BasicExample/BasicExample.xcodeproj -scheme BasicExample -destination 'generic/platform=iOS Simulator' build 通过（0 错误 0 警告）
- [x] 3.3 模拟器冒烟：连续闪退开关 → 自动崩溃循环 → 安全模式启动时控制台两条任务日志先于 UI（截图/日志证据）；DEBUG 直入路径同验证；修复重启后首页一次性横幅可见且再次启动不重复
- [x] 3.4 归档变更（spec 合并至 openspec/specs/example-apps/spec.md、移入 archive）；清理 openspec/changes/ 空残留目录
