# 设计：add-window-takeover-presentation

## Context

Change 3 已提供菜单页与 `presentSafeModeMenu()`（present 在宿主 key window rootVC 上，宿主跳过构建时无处可挂）。宿主分流范式：didFinishLaunching 首行 `if ALLaunchGuard.shared.start() { return true }`——自身 window/root VC 不构建。MPLaunch 类 APP 的 root 构建在 Launchable 模块 sceneDelegate 内，跳过 onceUponAScene 后同样无界面。约束：iOS 14（UIScene API iOS 13+ 可用）；UIKit 全部 `#if canImport(UIKit)` 隔离；swift test 不编译 UIKit 分支，需 xcodebuild iOS destination 验证。

## Goals / Non-Goals

**Goals:**
- 独立 UIWindow 接管：宿主零界面时有界面、漏分流时覆盖兜底。
- scene 就绪等待（willConnectNotification）+ 经典 delegate 全屏 frame 两栖。
- presentationStyle 可配置回退旧行为；显式接管 API。

**Non-Goals:**
- iPad 多 scene 并发策略精细治理（只取 foregroundActive/首个 scene，文档注明单窗口语义）。
- 窗口动画/转场特效。
- Example App 与端到端冒烟——Change 5。
- 修复完成后自动关窗/重启——设计上等待用户手动重启，窗口随进程结束消失。

## Decisions

### D1. 窗口管理器形态：final class 单例持有（非 enum 工具方法）
`ALLaunchGuardSafeModeWindowCoordinator`（internal）持有 `UIWindow?` 强引用与挂载状态；`install()` 幂等（已有窗口直接返回）。备选（ALLaunchGuard 直接持 window 属性）被否决：window 生命周期逻辑（scene 等待/重试）独立成类便于阅读与后续演进，且避免单例文件继续膨胀（已 300+ 行）。

### D2. 挂载时序：立即尝试 + willConnect 监听 兜底，不做定时轮询
install() 时先找 foregroundActive UIWindowScene → 有则 UIWindow(windowScene:) 直接 makeKeyAndVisible；无则注册 `UIScene.willConnectNotification` 一次性观察者，回调中再找（含 foregroundActive 过滤）挂载并移除观察者；若应用无 scene 配置（connectedScenes 恒空且通知不会来）→ 以 `UIWindow(frame: UIScreen.main.bounds)` 直接创建（经典 delegate 下 UIScreen.main 可用）。判定"无 scene 配置"不可靠（早期时序上区分不了"未连接"与"没有"）——处理：立即尝试失败后同时做两件事：监听 willConnect（有限时间内，如 5 秒超时后降级 frame 创建）+ 若 host window 已出现也可用。简化取舍：**超时降级**用一次 asyncAfter(5s) 检查——仍未挂载则 frame 创建。超时时长复用 survivalTimeout 无语义关联，取独立常量 5 秒并注释。

### D3. windowLevel：`.normal + 100` 而非 .alert/.statusBar
高于一切常规窗口、不与系统 alert 层冲突；菜单页自身的 UIAlert（未来）仍可正常弹出。

### D4. 分流点与显式 API
`activateSafeMode()` 中 `autoPresent == true` 时：presentationStyle == .dedicatedWindow（默认）→ coordinator.install()；== .presentOnRoot → 旧 `presentSafeModeMenu()`。新增 `public func activateSafeModeWindow()`（内部调 install，供宿主 return 前显式调用，幂等）。Config 新增枚举 `ALLaunchGuardPresentationStyle`（public enum, String raw 值便于调试）。

### D5. 不自动关窗
修复成功（reset）后窗口保持——此时进程仍处于"本次启动跳过了一切"状态，关窗会黑屏；等待用户手动重启是唯一正确语义（与微信一致）。reset 不触碰窗口（窗口归 coordinator 管，与安全模式状态解耦）。

## Risks / Trade-offs

- [多 scene（iPad 分屏）下挂错 scene] → 只取 foregroundActive（无则首个 keyWindow 场景），文档注明单窗口语义；Example 冒烟覆盖单 scene 常规路径。
- [willConnect 通知在 install 前已发（极端时序）] → install 先同步尝试一次再挂观察者；超时降级兜底闭环。
- [swift test 无法覆盖窗口逻辑] → 分流判定抽为纯函数可测（presentationStyle → 期望路径）；窗口挂载以 xcodebuild 编译 + Change 5 模拟器端到端验证。
- [UserDefaults 崩溃循环 + 窗口代码自身崩溃] → 粘滞 safeModeActive 已持久化，次启仍进安全模式（Change 1 语义），窗口重装。

## Migration Plan

1. 实现 + swift test（分流纯函数）+ xcodebuild iOS 构建通过 → 归档。
2. Change 5 Example App 端到端冒烟（正常启动→崩溃循环→窗口接管→修复→重启）。
3. 回滚 revert 即可。

## Open Questions

（无。）
