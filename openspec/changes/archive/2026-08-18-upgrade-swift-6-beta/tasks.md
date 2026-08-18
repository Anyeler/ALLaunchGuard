# 任务：upgrade-swift-6-beta

## 1. 清单文件

- [x] 1.1 Package.swift：swift-tools-version 5.5 → 6.0；swiftLanguageVersions [.v5] → [.v6]
- [x] 1.2 ALLaunchGuard.podspec：version → 2.2.0-beta.1（仅分支内占位，不打 tag）；swift_versions ['5.0'] → ['6.0']；description 同步提及 Swift 6 语言模式 beta

## 2. 源码最小标注集（零逻辑改动）

- [x] 2.1 ALLaunchGuard.swift：类声明追加 `: @unchecked Sendable`，注释锚定"stateLock 已串行化全部可变状态"外部同步依据（消 shared error + 通知闭包捕获 self 警告）
- [x] 2.2 ALLaunchGuardConfig.swift：`ALLaunchGuardConfig: Sendable`（编译器核验）；`ALPlaceholderColor: Sendable`（消非 UIKit 平台 systemOrange error）；**偏离：额外为 `ALLaunchGuardPresentationStyle` 显式追加 `Sendable`**——v6 语言模式下公共枚举不再隐式合成 Sendable，计划未预判（String 枚举平凡 Sendable，零语义变化）
- [x] 2.3 ALLaunchGuardFixAction.swift：exitHandler 类型改 `@Sendable () -> Void`；派发点改快照捕获 `[exitHandler]`；load-bearing 时序注释保留/加强（禁 Task 化）
- [x] 2.4 ALLaunchGuardSafeModeWindow.swift：协调器追加 `: @unchecked Sendable`，注释锚定"主线程断言 + 自 hop 主队列"结构保证；协调器内约 18 个跨隔离 UIKit 警告为 beta 接受态，不修
- [x] 2.5 **计划外最小处置**：ALLaunchGuard.swift `perform` 编排层的 action/completion 在新编译器（Swift 6.3）下从计划预期的 warning 升级为 sending error，以 `nonisolated(unsafe)` 快照捕获收口（运行时语义不变；根治即协议族 Sendable 化，留待转正 3.0）

## 3. 既有潜在竞态收口

- [x] 3.1 ALLaunchGuard.swift：handleDidEnterBackground() / handleWillTerminate() 的 storage 写入包入 withStateLock（与任意线程锁内读的 shouldEnterSafeMode 同锁串行化）

## 4. 测试侧最小适配

- [x] 4.1 ALLaunchGuardTests.swift：全局 `let immediateScheduler / noOpScheduler` 改无参顶层 func（语义等价）；**计划外最小处置**：ALLaunchGuardFixActionTests 时序锚定用例中 exitHandler 闭包升级为 @Sendable 后不得捕获可变局部变量，改用锁保护的 RestartExitRecorder（记录点实际均在主队列执行，锁仅为编译级标注）；逃生舱 testTarget swiftLanguageMode .v5 未使用

## 5. 验证

- [x] 5.1 swift build 与 swift test：0 error（65/65 测试全绿）；实测 warning：macOS 库 target 3 个（survivalScheduler work ×1 + 后台清理闭包捕获 completion ×2）、iOS 交叉编译 21 个（含前者 3 个 + 协调器跨隔离 UIKit ×16 + VC init/非隔离转换 ×2）——类别与 beta 接受态清单一致，数量与计划预估（约 23）相当，无新增类别
- [x] 5.2 Examples 零改动确认（BasicExample SWIFT_VERSION=5.0 保持；MPLaunchExample 已 gitignore）
- [x] 5.3 TSan 无数据竞争（swift test -sanitize=thread 全绿）
- [x] 5.4 iOS 14 模拟器交叉编译：0 error / 21 warning（均为 beta 接受态类别，与 5.1 清单一致）
- [x] 5.5 BasicExample BUILD SUCCEEDED（Swift 5 app target 消费 v6 库，验证双向兼容）
