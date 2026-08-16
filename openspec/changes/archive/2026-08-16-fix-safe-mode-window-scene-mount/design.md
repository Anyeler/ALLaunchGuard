# 设计：fix-safe-mode-window-scene-mount

## Context

缺陷定位（Example 冒烟实证）：① `activateSafeModeWindow()` 用 `DispatchQueue.main.async` 派发 install，而 willConnectNotification 在 didFinishLaunching 返回后立即发出——install 执行时通知已过，观察者注册太晚；② scene 候选过滤仅 `.foregroundActive`，早期/回调时 scene 常为 `foregroundInactive` 被拒；③ 超时降级的 frame window（无 windowScene）在 scene 生命周期的 App 上不显示（黑屏）；④ 经典 delegate（无 scene manifest）时 connectedScenes 恒空，被迫等满 5 秒超时。

## Goals / Non-Goals

**Goals:** 三处修正（同步时机/候选放宽/manifest 检测立即降级），消除两类黑屏；保持幂等与既有 46 测试全绿。

**Non-Goals:** iPad 多 scene 精细策略；超时时长调优；UI 转场动画。

## Decisions

### D1. 同步 install：已在主线程直接执行
`activateSafeModeWindow()` 改为 `if Thread.isMainThread / DispatchQueue.getSpecific` 判定：主线程同步调 install，否则 dispatch main。install 内部保留 dispatchPrecondition(.onQueue(.main))。收益：didFinishLaunching 首行（主线程）调用时观察者先于 willConnect 注册。

### D2. scene 候选两级匹配
第一级 foregroundActive；第二级任意 UIWindowScene（`scenes.compactMap { $0 as? UIWindowScene }.first`）。绑定 foregroundInactive scene 的窗口在该 scene 激活后自然可见（系统行为），无需自行等待激活。

### D3. scene manifest 检测决定是否等待
internal `sceneManifestDetector: () -> Bool`（默认读 `Bundle.main.infoDictionary?["UIApplicationSceneManifest"] != nil`，可注入测试）：install 无可用 scene 时——无 manifest → 立即 frame 降级创建；有 manifest → 注册 willConnect 观察者 + 5 秒超时降级（保留）。scene App 中 frame 窗口不可见的场景仅在超时兜底出现（极端异常），可接受。

### D4. 测试策略
manifest 检测与"等待或立即降级"决策抽 internal 纯函数（无 UIKit 依赖）表驱动测试：无 scene + 无 manifest → immediate；无 scene + 有 manifest → waitWithTimeout；有 scene → attach。窗口创建路径仍靠 iOS 编译 + Example 冒烟复验。

## Risks / Trade-offs

- [foregroundInactive scene 一直不激活（极端）] → 窗口不可见但安全模式状态正确（粘滞），重启仍进安全模式；概率极低接受。
- [main thread 判定遗漏非主线程调用] → 保留非主线程 dispatch main 分支，仅时序不同不影响正确性。
- [Bundle.main 在测试环境为 xctest runner] → 检测函数可注入，库单测不受影响。

## Migration Plan

修复 → swift test + xcodebuild + MPLaunchExample（scene 路径）与 BasicExample（经典路径）冒烟复验 → 归档。属 2.0 发布前的缺陷修复，不单独发版。

## Open Questions

（无。）
