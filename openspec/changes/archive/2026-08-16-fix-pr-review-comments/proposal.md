# 提案：fix-pr-review-comments

## Why

PR #2（2.0 重构）收到 Copilot 两条评审意见，均有效：① `ALLaunchGuardSafeModeWindow.install()` 内部的 `dispatchPrecondition(.onQueue(.main))` 在 Release（-O）构建失败同样致命停机——虽为 internal 且现有调用链（activateSafeModeWindow 主线程同步/非主线程派发）保证主线程，但与 fix-lifecycle-review-findings 确立的"防闪退库不在宿主误用时于 Release 崩溃"原则不一致，未来新增调用点存在隐患；② BasicExample 将 HomeViewController 直接设为 window.rootViewController，但其"直接进入安全模式"调试入口配置在 navigationItem 上，未包 UINavigationController 导致导航栏不显示、该 DEBUG 入口不可达。

## What Changes

- `install()` 的 `dispatchPrecondition` 降级为 `assert(Thread.isMainThread, ...)`，注释说明与公共入口一致的 Debug 断言/Release 容忍策略。
- BasicExample AppDelegate：rootViewController 改为 `UINavigationController(rootViewController: HomeViewController())`，导航栏与 navigationItem 调试入口恢复可见。

## Capabilities

### New Capabilities

（无。）

### Modified Capabilities

（无——safe-mode-window 主 spec 的挂载需求不含线程断言实现细节；example-apps 需求已要求"直接进入安全模式"调试操作可达，本变更属缺陷修复使其真正满足。）

## Impact

- Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift（一行断言替换 + 注释）；Examples/BasicExample/BasicExample/AppDelegate.swift（一行包裹）。
- 验证：swift test 回归、iOS 构建、Example 构建与冒烟截图（导航栏 + 调试入口可见）。
