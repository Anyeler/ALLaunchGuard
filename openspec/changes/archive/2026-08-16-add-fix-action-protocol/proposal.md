# 提案：add-fix-action-protocol

## Why

当前安全模式的修复能力只有一个 `fixHandler` 闭包 + 单按钮（ALLaunchGuardViewController L16/L153-157），无法满足"安全模式页为可扩展菜单列表、点击某项才开始对应修复"的需求。微信的菜单式修复页与天猫"业务注册修复行为"是业界标杆，需要把修复动作抽象为协议，由库统一编排（执行 → 首个成功动作退出安全模式 → 通知宿主），为后续菜单 UI 变更（add-safe-mode-menu-ui）提供非 UI 的可测层。

## What Changes

- 新增公共协议 `ALLaunchGuardFixAction`（title / iconSystemName / isDestructive / perform(completion:)），用户点击才执行。
- 新增内置动作 `ALLaunchGuardClearCacheAction`（清理 Library/Caches）与便捷闭包包装 `ALLaunchGuardClosureAction`。
- `ALLaunchGuard` 新增 `public var fixActions: [ALLaunchGuardFixAction]` 注册；新增编排方法（internal/公共最小面）：执行指定动作 → 成功时触发一次 `reset()`（退出安全模式、清粘滞标记与计数）→ 通知委托。
- `ALLaunchGuardDelegate` 追加可选回调 `launchGuard(_:didFinishFixAction:success:)`（extension 默认空实现，零破坏）。

## Capabilities

### New Capabilities

- `fix-actions`：可扩展的修复动作能力——动作协议契约（元数据 + 点击执行 + 恰好一次 completion）、注册与编排语义（首个成功动作退出安全模式、失败可重试不退出）、内置动作与闭包包装。

### Modified Capabilities

（无——crash-detection 主 spec 的判定需求不变；本变更只新增修复动作层。）

## Impact

- 新增 `Sources/ALLaunchGuard/ALLaunchGuardFixAction.swift`；修改 `Sources/ALLaunchGuard/ALLaunchGuard.swift`（fixActions 属性 + 编排 + 默认动作集成）、`Sources/ALLaunchGuard/ALLaunchGuardDelegate.swift`（追加可选回调）。
- 测试：mock 动作验证编排语义（成功 reset 仅一次 / 失败不 reset 不回调 / 内置动作集）。
- 不涉及 UI（菜单页属 add-safe-mode-menu-ui）。
- OC 互操作：FixAction 为 Swift 协议，README 将注明 Swift-only（属文档变更）。
