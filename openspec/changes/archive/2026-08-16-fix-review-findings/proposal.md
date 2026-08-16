# 提案：fix-review-findings

## Why

三维度代码评审（完整性/正确性/影响面）发现 2 个必须修复的缺陷与 4 个应修复问题：① scene 宿主中 5 秒超时降级创建的 frame 窗口不可见，且 show() 清理观察者 + 幂等门控使 scene 随后连接时永久无法恢复挂载（主线程阻塞 >5s 的崩溃循环 App 典型场景必现）；② 升级残留计数场景下（1.x 升 2.0 首启计数达阈值）、或宿主忘记注册 fixActions 时，粘滞安全模式无任何用户出口（被困，只能删 App 重装）；③ presentSafeModeMenu 无防重入可叠加多页并发执行同一动作；④ 菜单页行数快照与内容实时读取语义混杂；⑤ start() 缺主线程断言存在数据竞争面；⑥ README 缺存储协议文档、迁移章节 3 处措辞不实/缺口。

## What Changes

- 窗口超时降级改为"可恢复"：超时创建 frame 窗口后保留 willConnect 观察者；scene 连接时若存在未挂 scene 的降级窗口，废弃并以 UIWindow(windowScene:) 重新挂载（spec 行为修正）。
- 空 fixActions 兜底：安全模式页在 fixActions 为空时自动提供内置"重置安全模式并重启"动作（内部实现 reset， destructive 样式），消除无出口陷阱（spec 行为修正，同时覆盖升级残留场景）。
- presentSafeModeMenu 防重入：已展示安全模式页（顶层 presented 或窗口 root）时跳过。
- 菜单页改为完整快照语义：viewDidLoad 快照 actions 数组，行数/渲染/执行统一使用快照。
- start() 增加主线程前置断言（dispatchPrecondition，与 install 一致）。
- README：新增存储协议章节（新字段/向后兼容/降级后果）、迁移章节修正（升级首启可能触发安全模式且必须注册至少一个 fixAction 的提示、.presentOnRoot 仅回退挂载方式、markLaunchSuccessful 不退出安全模式、旧 VC 按钮文案不可配）、How It Works 补 didEnterBackground 漏计边界说明。

## Capabilities

### New Capabilities

（无。）

### Modified Capabilities

- `safe-mode-window`：超时降级策略修正——降级窗口可被 scene 连接后的正式挂载取代，不再永久阻断。
- `safe-mode-ui`：空动作列表行为修正——由纯空态提示改为自动提供内置重置退出动作；动作数据快照语义固化。

## Impact

- 修改 Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift、ALLaunchGuardSafeModeViewController.swift、ALLaunchGuard.swift、ALLaunchGuardFixAction.swift（内置重置动作，若放此处）；README.md。
- 测试：空 fixActions 兜底动作、presentSafeModeMenu 防重入（可测部分）、快照语义；既有 47 测试回归。
- 两 Example 冒烟复验（scene 超时路径难以稳定复现，以代码走查 + 常规路径复验为准）。
