# 设计：fix-lifecycle-review-findings

## Context

评审依据（Apple 官方核实）：dispatchPrecondition 在 -O Release 构建失败同样停机（非 Debug-only）；系统可随时 disconnect 后台/挂起 scene 并释放其 window 层级，scene 重连时再次发出 willConnectNotification；assert() 为 Debug-only。当前实现：start() L149-155 用 dispatchPrecondition 且注释错误声称 Debug 断言；窗口协调器正式挂载成功后 cleanupMountWaiters 移除 willConnect 观察者，断连后无法自愈。其余评审项（B/C/D/E/G/H 主逻辑）确认正确，仅文档与渐进加固。

## Goals / Non-Goals

**Goals:** 修复 2 个 P1（Release 崩溃面 + scene 断连自愈），补 3 处文档与弃用注释锚定；50 测试回归全绿。

**Non-Goals:** UIKit 窗口状态机的自动化测试（swift test 无法编译 UIKit 分支，列入演进项——后续可建 iOS destination 测试 target 挂 CI）；UIScreen.main 替代实现（仅注释锚定，正常路径已走 windowScene）；perform() 编排层变更（已正确）。

## Decisions

### D1. 断言降级：dispatchPrecondition → assert（对应 P1①）
`start()`/`markLaunchSuccessful()`/`reset()` 三处统一 `assert(Thread.isMainThread, "...")`：Debug 构建暴露误用，Release 容忍（不再自造 crash）。doc comment 声明"应在主线程调用（didFinishLaunching 首行天然满足）；Debug 构建违反将触发断言"。备选（保留 precondition + 修注释）被否决：防闪退库不应在宿主误用时于 Release 崩溃，容忍+文档优于致命。

### D2. 观察者持续保持 + 分支①去清理（对应 P1②）
`handleSceneWillConnect` 分支①（当前窗口已挂 scene）改为直接 return，**不**调用 cleanupMountWaiters；cleanupMountWaiters 仅保留给超时任务取消场景与 deinit；willConnect 观察者自 install 注册后持续存在至 deinit。断连重连路径：scene 断连后旧 window 的 windowScene 被系统置空（层级释放），重连 willConnect 时分支②（windowScene == nil 或 window == nil）以新 scene 重建窗口、迁移 root、废弃旧窗——复用现有分支②逻辑，零新状态。幂等：分支①拦截健康状态下的重复连接通知。

### D3. 断连后的旧窗判定
不监听 didDisconnectNotification（新观察面）：断连后旧 UIWindow 对象仍被协调器强持有但 windowScene 为 nil（不可见无害），重连时分支②重建并释放旧引用。避免引入 disconnect 观察者的状态复杂度。

### D4. 文档补齐
README：已知限制小节（iOS 15/16 预热 bug 下预热回收计为一次闪退的概率说明 + 真实启动 5 秒存活自然复位）、SwiftUI 接入小节（App.init 主线程先于 didFinishLaunching，注册 fixActions + start() 门控 body 分流）、线程契约（三方法主线程）。UIScreen.main 两处加注释："iOS 26.0 起弃用，仅无 scene 兜底路径使用，正常路径为 UIWindow(windowScene:)"。

## Risks / Trade-offs

- [观察者持续存在的心智负担] → 分支①幂等返回成本为零；deinit 清理兜底；注释说明设计意图。
- [Release 下后台线程调用 start() 的数据竞争仍存在] → 容忍优于崩溃（库使命优先），Debug 断言 + 文档双通道约束；与 assert 语义一致。
- [断连判定依赖 windowScene == nil] → 系统断连即移除 window 的 scene 归属（官方属性语义），重连走分支②；若个别系统版本行为差异，重复 willConnect 幂等无害。

## Migration Plan

修复 → swift test 50 全绿 → xcodebuild iOS 构建 0 警告 → BasicExample 快速冒烟（安全模式两态）→ 归档。

## Open Questions

（无。）
