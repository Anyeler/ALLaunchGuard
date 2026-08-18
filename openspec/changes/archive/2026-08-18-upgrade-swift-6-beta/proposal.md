# 提案：upgrade-swift-6-beta

## Why

Swift 6 语言模式试编译（-swift-version 6，macOS 目标 + iOS 14 模拟器交叉编译）实测诊断量极小：4-5 个 error 全部高度同构于既有 stateLock 外部同步设计，均有最小标注级修复；约 23 个 warning 集中于窗口协调器跨隔离 UIKit 访问（约 18 处）等，属可记录接受态。为提前验证 Swift 6 生态兼容性且不影响 main 上服务旧工具链的 2.1.0，在长期分支 `beta/swift-6`（基于 origin/main，不合入 main）上一步切换 v6 语言模式，无需 -strict-concurrency=complete 警告级过渡。

## What Changes

- **清单文件**：Package.swift swift-tools-version 5.5 → 6.0、swiftLanguageVersions [.v5] → [.v6]；podspec version → 2.2.0-beta.1（仅分支内占位，不打 tag 不 pod trunk push）、swift_versions ['5.0'] → ['6.0']、description 同步提及 Swift 6 语言模式 beta。
- **源码最小标注集（约 7 行，零逻辑改动）**：ALLaunchGuard 类追加 `: @unchecked Sendable`（锚定 stateLock 外部同步依据）；ALLaunchGuardConfig 追加 `: Sendable`（编译器可核验）；ALPlaceholderColor 追加 `: Sendable`（无状态类，消除非 UIKit 平台 static let error）；RestartAction 的 exitHandler 类型改 `@Sendable () -> Void` 并以快照捕获派发（保持 load-bearing 时序）；窗口协调器追加 `: @unchecked Sendable`（锚定主线程断言 + 自 hop 主队列结构保证）。
- **既有潜在竞态收口（审计发现，一并修复）**：handleDidEnterBackground / handleWillTerminate 的 storage 写入包入 withStateLock，与任意线程锁内读的 shouldEnterSafeMode 同锁串行化。
- **测试侧最小适配**：全局 scheduler 常量改无参顶层 func（非 Sendable 函数类型全局量在 v6 下升级为 error）。
- **公共 API 签名破坏**：仅 exitHandler 内部类型一处（internal，非公共 API 面）；其余零签名变化。

## Capabilities

### New Capabilities

（无新能力域。）

### Modified Capabilities

- `crash-detection`：ADDED"生命周期通知写入串行化"需求（通知回调的 storage 写入须经 stateLock 串行化）。

## Impact

- `Package.swift`、`ALLaunchGuard.podspec`、`Sources/ALLaunchGuard/ALLaunchGuard.swift`、`Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`、`Sources/ALLaunchGuard/ALLaunchGuardFixAction.swift`、`Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`、`Tests/ALLaunchGuardTests/ALLaunchGuardTests.swift`。
- Examples/BasicExample 与 MPLaunchExample 零源码改动（app target 保持 SWIFT_VERSION=5.0，Swift 5 app 消费 v6 库合法）。
- 分发策略：beta 分支独立演进，main→beta 周期性 merge（禁 rebase/force-push）；转正时由 beta 向 main 开 PR。
