# 任务：add-window-takeover-presentation

## 1. 配置与分流（可 swift test 部分，TDD）

- [x] 1.1 先写测试：ALLaunchGuardConfig.presentationStyle 默认值 == .dedicatedWindow；自定义 .presentOnRoot 赋值断言；分流纯函数（internal，presentationStyle + autoPresent → 期望展示路径枚举）表驱动测试
- [x] 1.2 修改 `Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`：新增 `public enum ALLaunchGuardPresentationStyle { case dedicatedWindow, presentOnRoot }` 与 `presentationStyle` 字段（默认 .dedicatedWindow，init 带默认参数）
- [x] 1.3 `Sources/ALLaunchGuard/ALLaunchGuard.swift`：activateSafeMode() 的 autoPresent 分流改为按 presentationStyle（dedicatedWindow → 窗口接管安装；presentOnRoot → presentSafeModeMenu()）；分流判定抽 internal 纯函数

## 2. 窗口接管器（新文件，UIKit）

- [x] 2.1 新建 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`（#if canImport(UIKit)）：internal final class 窗口协调器——强持有 UIWindow；`install(rootViewController:)` 幂等（已有则直接返回）；windowLevel = .normal + 100；挂载策略：①立即找 foregroundActive UIWindowScene → UIWindow(windowScene:)；②无则监听 UIScene.willConnectNotification（回调中重找并挂载后移除观察者）；③5 秒超时仍未挂载 → UIWindow(frame: UIScreen.main.bounds) 降级创建；makeKeyAndVisible；iOS 14 安全 API
- [x] 2.2 `ALLaunchGuard.swift` 新增 `public func activateSafeModeWindow()`：以菜单页（ALLaunchGuardSafeModeViewController，注入 self）为 root 调协调器 install（幂等）；自动分流路径与显式入口共用

## 3. 验证与收口

- [x] 3.1 swift test 全绿（43 存量 + 新增配置/分流测试）；swift build 0 新增警告
- [x] 3.2 xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator' build（独立 derivedDataPath）0 错误 0 警告（含新窗口文件全部代码）
- [x] 3.3 代码走查自查：install 幂等、观察者超时后清理（避免泄漏）、窗口不自动关闭、reset 不触碰窗口
