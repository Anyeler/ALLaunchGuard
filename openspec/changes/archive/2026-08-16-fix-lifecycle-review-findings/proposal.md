# 提案：fix-lifecycle-review-findings

## Why

以 Apple 官方文档为标尺的生命周期评审（研究员核实官方语义 + 评审员逐项对照代码）确认核心判定逻辑正确，但发现 2 个 P1 与多项 P2：① `start()` 的 `dispatchPrecondition(.onQueue(.main))` 在 Release（-O）构建失败同样致命停机（官方语义，非 Debug-only），宿主误从后台线程调用时 Release 包直接崩在库内——与"防闪退库"使命矛盾，且注释错误声称"Debug 断言"；② 官方允许系统随时 disconnect 后台 scene 并释放其 window 层级，正式挂载后 willConnect 观察者被清理，scene 断连后用户回前台修复页丢失且无重挂（宿主已跳过 UI 构建 → 黑屏，只能杀进程重启兜底）；③ 文档缺口：iOS 15/16 预热 bug 盲区、markLaunchSuccessful/reset 线程契约、SwiftUI 接入范式；④ UIScreen.main 已被 SDK 标注 iOS 26.0 弃用，兜底路径需注释锚定。

## What Changes

- `start()`：`dispatchPrecondition` 改为 `assert(Thread.isMainThread)`（Debug 断言 + Release 容忍），doc comment 如实声明主线程约束与 Release 行为；`markLaunchSuccessful()` / `reset()` 同步补主线程 assert 与文档契约。
- 窗口协调器：正式挂载成功后**不再**移除 willConnect 观察者（观察者生命周期延长至协调器 deinit）；`handleSceneWillConnect` 分支①（已挂载）改为仅幂等返回不清理——scene 被系统断连后重连时经分支②以新 scene 重建窗口迁移 root，修复断连黑屏。
- README：补"已知限制"（iOS 15/16 预热 bug 场景与自然复位说明）、SwiftUI 接入小节（App.init 时序与门控范式）、线程契约说明（start/markLaunchSuccessful/reset 主线程）。
- UIScreen.main 两处兜底使用处加弃用注释锚定（iOS 26.0 起弃用，仅无 scene 兜底路径使用）。
- 窗口状态机的自动化测试缺口（UIKit 分支无法进 swift test）列入后续演进，不在本变更实施。

## Capabilities

### New Capabilities

（无。）

### Modified Capabilities

- `safe-mode-window`：scene 断连自愈——正式挂载后保留 scene 连接监听，断连重连时以新 scene 重建迁移（原"重新挂载后清理监听"改为"监听保持至协调器释放"）。

## Impact

- 修改 `Sources/ALLaunchGuard/ALLaunchGuard.swift`（断言与线程契约）、`Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`（观察者生命周期与分支①）、`README.md`。
- 测试：既有 50 测试回归；窗口分支逻辑以 iOS 构建验证（自动化 UIKit 测试为演进项）。
