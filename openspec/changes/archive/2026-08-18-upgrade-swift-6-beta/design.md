# 设计：upgrade-swift-6-beta

## Context

实测诊断基线（两份独立视角报告一致，macOS 目标 + iOS 14 模拟器 destination JSON 交叉编译，-swift-version 6）：

**Errors（4-5 个，阻断编译，全部有最小标注级修复）**：
- ALLaunchGuard.swift `static let shared`：类非 Sendable；
- ALLaunchGuardConfig.swift `static let default`：Config 非 Sendable；
- ALLaunchGuardConfig.swift `ALPlaceholderColor.systemOrange`：仅非 UIKit 平台（macOS 测试专属）；
- ALLaunchGuardFixAction.swift RestartAction `main.async { self.exitHandler() }`：sending self；
- ALLaunchGuardSafeModeWindow.swift 协调器自 hop `main.async { self.install(...) }`：sending self（仅 iOS 目标）。

**Warnings（约 23 个，beta 接受态，不修）**：窗口协调器跨隔离访问 UIKit API 约 18 处、通知 @Sendable 闭包捕获 self 2 处（标注 @unchecked Sendable 后消除）、后台清理闭包捕获 completion 2 处、survivalScheduler work 参数 1 处、VC init 调用 2 处。

**关键事实**：SafeModeViewController 零诊断（UIViewController 子类 @MainActor 自动推断干净）；错误高度同构于既有 stateLock 外部同步设计；无需 -strict-concurrency=complete 警告级过渡，可一步切 v6。

## Goals / Non-Goals

**Goals:** v6 语言模式 0 error 编译（macOS swift test + iOS 交叉编译）；最小标注集（约 7 行）零逻辑改动；随附收口一处既有潜在竞态；公共 API 零签名破坏（exitHandler 为 internal 类型细化）；Examples 零改动。

**Non-Goals（beta 接受态，不修）:** 约 23 个 warning；协议族 Sendable 化；协调器 @MainActor 化；README 之外文档变更。

## Decisions

### D1. 隔离模型：维持 NSLock + @unchecked Sendable（否决 @MainActor 单例）

- @MainActor 单例会把"Release 容忍后台误调"的既定设计（防闪退库不制造新崩溃面）变成编译期/运行时强制；收窄 shouldEnterSafeMode 任意线程读契约；hammer 并发测试资产作废。
- `ALLaunchGuard: @unchecked Sendable` 是对"stateLock 已串行化全部可变状态 + TSan 全绿 + 8 路 hammer 锚定"这一已验证事实的诚实标注；标注处注释必须锚定该外部同步依据（锁纪律红线见 harden-thread-safety design D1）。
- 窗口协调器同理：`@unchecked Sendable` 锚定"install 内主线程断言 + 非主线程自 hop 主队列"的结构保证——跨隔离发送 self 的全部落点最终在主队列串行执行。协调器内约 18 个跨隔离 UIKit 访问警告为 beta 接受态。
- 被否决备选：@MainActor 单例（上述理由）；协调器整体 @MainActor 化（deinit 隔离访问编译行为待验证、改动面与回归风险放大，记入转正路线图）；-strict-concurrency=complete 分阶段过渡（诊断量极小，一步切 v6 即可）；swift-tools 5.9/5.10 声明 v6（不可行——SwiftVersion.v6 枚举随 tools 6.0 引入）。

### D2. Beta 接受态与转正路线图

- **Beta 接受态**：约 23 个 warning 不修，显式记录为接受态（防止被误读为"未完成"）。
- **转正路线图（留待转正时按 3.0 破坏性版本处理）**：
  1. 协议族 Sendable 化——FixAction / Storage / Delegate 追加 Sendable + completion 参数 @Sendable 化，属对外 source-breaking；
  2. 协调器 @MainActor 化——消除 18 个跨隔离 UIKit 警告；
  3. 转正时由 beta 向 main 开 PR，删除 beta 分支。

### D3. RestartAction 时序保持（load-bearing）

exitHandler 类型改 `@Sendable () -> Void`；派发点改 `DispatchQueue.main.async { [exitHandler] in exitHandler() }` 快照捕获（消除 sending self）。**禁止把此处 Task 化**：`completion(true)` 先同步执行 → 编排层 reset 先入主队列 → exit 晚一拍派发，依赖主队列 FIFO 保证粘滞标记清除先于进程终止。既有注释保留并加强。

### D4. 既有潜在竞态收口（审计发现）

`handleDidEnterBackground()` / `handleWillTerminate()`（主队列通知回调）当前在锁外直接写 storage，与任意线程锁内读的 shouldEnterSafeMode 未经同一锁串行化——将其 storage 写入包入 withStateLock。回调在主队列、锁为 NSLock 非递归且临界区内不触达宿主代码，无新死锁面；行为语义不变。

### D5. 测试侧适配与逃生舱

全局 `let immediateScheduler / noOpScheduler`（非 Sendable 函数类型全局量，v6 下升级为 error）改无参顶层 func，语义等价。Mock 类预判无需改动（局部创建、主线程串行；@unchecked Sendable 标注后 concurrentPerform 捕获合法化）。残余诊断以真实编译输出为准逐项最小处置；逃生舱：testTarget 声明 `swiftLanguageMode: .v5`（tools 6.0 API），仅在确有必要时使用并在 tasks 记录原因。

### D6. 清单与分支策略

- Package.swift：swift-tools-version 6.0 + swiftLanguageVersions [.v6]。
- podspec：version 2.2.0-beta.1（仅分支内占位，**不打 tag、不 pod trunk push**）；swift_versions ['6.0']（消费者需 Xcode 16+，beta 定位即隔离；main 上 2.1.0 继续服务旧工具链）；description 同步。
- 分支 `beta/swift-6` 基于 origin/main（含 PR #3/#4）；推送远端但不合入 main；main→beta 周期性 merge（**禁 rebase/force-push**）。

## Risks / Trade-offs

- [@unchecked Sendable 掩盖未来真实竞态] → 标注处锚定 stateLock / 主线程结构保证注释；锁纪律红线 + hammer 测试 + TSan 常态化。
- [test target v6 诊断超出预判] → 以真实编译输出逐项处置；逃生舱 testTarget swiftLanguageMode .v5。
- [18 个协调器警告被误读为未完成] → 本 design 与 tasks 显式记录"beta 接受态 + 转正路线图"。
- [RestartAction FIFO 时序被未来 Task 化打破] → load-bearing 注释 + 时序锚定测试 + 本文档明令禁用 Task。
- [误打 tag / push trunk] → AGENTS.md 明令禁止，beta 版本号仅分支内占位。

## Migration Plan

清单 + 标注（同一实施批次）→ 测试适配 → swift build / swift test 自检（0 error；warning 与接受态清单一致）→ 归档（后续任务：README beta 说明、提交推送）。

## 实施偏离记录（apply 阶段实测，Swift 6.3.3 工具链）

1. **ALLaunchGuardPresentationStyle 需显式 Sendable**：v6 语言模式下公共枚举不再隐式合成 Sendable，导致 ALLaunchGuardConfig: Sendable 编译失败；显式追加标注（String 枚举平凡 Sendable，零语义变化）。
2. **perform 编排层 sending 升级为 error**：计划基线将“后台清理闭包捕获 completion”等归为 warning，但 Swift 6.3 下 `perform` 内 action/completion 跨隔离发送为硬 error（#SendingRisksDataRace）；最小收口：`nonisolated(unsafe)` 局部快照（运行时语义不变），根治（协议族 Sendable 化）仍在转正 3.0 路线图。
3. **测试时序锚定用例适配**：exitHandler 升级 @Sendable 后，用例内捕获可变局部变量的注入闭包成为 error（#SendableClosureCaptures）；改用锁保护的 RestartExitRecorder（记录点实际均在主队列，锁仅为编译级标注）。
4. **实测 warning 分布**：macOS 库 target 3 个；iOS 交叉编译 21 个（含协调器跨隔离 UIKit ×16、VC init/非隔离转换 ×2）——均在 beta 接受态范畴，无新增类别。
5. **逃生舱未使用**：test target 全程 v6 编译，未启用 swiftLanguageMode .v5。

## Open Questions

（无。）
