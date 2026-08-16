# 设计：fix-review-findings

## Context

评审缺陷定位：① ALLaunchGuardSafeModeWindow.handleFallbackTimeout 在 scene 宿主创建无 scene 的不可见窗口，show() 的 cleanupMountWaiters 移除 willConnect 观察者 + install 幂等门控拦截重试 → 永久黑屏；② 粘滞 safeModeActive 唯一出口是修复动作成功/reset，fixActions 为空时无出口；③ presentSafeModeMenu 每次新建 VC present 无重入门控；④ 菜单页 states 快照行数但 configure/didSelect 实时读 fixActions；⑤ start() 无主线程断言；⑥ README 六处文档缺口/措辞不实。

## Goals / Non-Goals

**Goals:** 修复 ①②（P1/Critical）与 ③④⑤（P2），补齐 ⑥ 文档；47 存量测试全绿 + 新增测试。

**Non-Goals:** perform 编排层并发锁（UI 层防重入已消除主要入口，双页场景已由 ③ 修复）；start() 主线程约束的运行时自动派发（仅断言 + 文档）。

## Decisions

### D1. 超时降级窗口可恢复（对应缺陷 ①）
状态机扩展：install 后存在三种窗口状态——未创建 / 已挂 scene / 降级 frame（windowScene == nil）。超时创建降级窗口时**不清理** willConnect 观察者（仅取消超时任务）；willConnect 回调逻辑改为：若当前窗口已挂 scene → 清理返回；若为降级 frame 窗口或 nil → 以新 scene 创建 UIWindow(windowScene:)、迁移同一个 rootViewController、废弃旧降级窗口（.isHidden = true 后置 nil）、makeKeyAndVisible、清理观察者。幂等语义不变（对外仍只有一个有效窗口）。

### D2. 内置退出动作（对应缺陷 ②）
新增 `public final class ALLaunchGuardResetSafeModeAction: ALLaunchGuardFixAction`（放 ALLaunchGuardFixAction.swift）：标题"重置安全模式"、图标 "arrow.counterclockwise"、isDestructive true；perform 直接 completion(true)（成功后编排层自动 reset——与"首个成功动作触发 reset"编排天然一致，无需特殊逻辑）。菜单页 viewDidLoad 快照时：`launchGuard.fixActions.isEmpty ? [ALLaunchGuardResetSafeModeAction()] : fixActions 快照`。备选（空态页加重置按钮）被否决：复用动作编排/状态机，代码路径统一。

### D3. presentSafeModeMenu 防重入（对应缺陷 ③）
present 前检查：key window rootViewController 顶层链（含 presentedViewController 递归）是否已存在 ALLaunchGuardSafeModeViewController，存在则跳过。检查放 present 闭包内（主队列）。

### D4. 菜单页完整快照（对应缺陷 ④）
viewDidLoad 中 `let snapshotActions: [ALLaunchGuardFixAction] = ...`（含 D2 兜底），states 对应快照；numberOfRows/configure/didSelect 全部用 snapshotActions。注释同步更新（原"快照一次"声明落地为真）。

### D5. start() 主线程断言（对应缺陷 ⑤）
`start()` 首行 `dispatchPrecondition(condition: .onQueue(.main))`，doc comment 注明主线程约束（didFinishLaunching 首行调用天然满足）。markLaunchSuccessful 增加 `guard didStart` 防御（评审建议 5，顺带）。

### D6. README 补齐（对应 ⑥）
新增"自定义存储"小节（协议三新字段、no-op 降级后果——尤其 safeModeActive 不持久化则粘滞防护失效、升级示例代码）；Migration 增补：升级首启可能立即触发安全模式的场景说明 + "必须至少注册一个 fixAction"（并注明空列表时库会自动提供重置动作兜底）；§3 .presentOnRoot 仅回退挂载方式措辞修正；§4 补 markLaunchSuccessful 不退出安全模式；§2 补旧 VC 按钮文案不可配说明；How It Works 计数表补 didEnterBackground 边界行（进后台后回前台 5 秒内崩溃会计漏一次，宁漏报不误报取舍）。

## Risks / Trade-offs

- [降级窗口迁移 rootViewController 的转场闪烁] → 极端路径（>5s 阻塞）才触发，可见性优先于闪烁。
- [内置重置动作被宿主误依赖] → 仅空列表时注入；文档注明推荐注册业务动作。
- [start() 断言在既有后台线程调用宿主崩溃] → 属误用暴露（Debug 断言），文档约束 + 与 install 风格一致。

## Migration Plan

修复 → swift test（47 + 新增）→ xcodebuild iOS 构建 → BasicExample 常规冒烟复验（正常/安全模式两态）→ 归档。2.0.0 发布前完成。

## Open Questions

（无。）
