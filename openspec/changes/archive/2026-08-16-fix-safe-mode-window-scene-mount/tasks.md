# 任务：fix-safe-mode-window-scene-mount

## 1. 挂载策略修复（TDD：先写失败测试）

- [x] 1.1 先写纯函数测试：挂载决策函数表驱动（有 scene → attach；无 scene + 无 manifest → immediateFrameFallback；无 scene + 有 manifest → waitSceneWithTimeout）；sceneManifestDetector 注入
- [x] 1.2 修改 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`：scene 候选两级匹配（foregroundActive 优先，任意 UIWindowScene 兑底）；无 scene 时按 manifest 检测（internal 注入，默认 Bundle.main.infoDictionary 读 UIApplicationSceneManifest）决定立即 frame 降级或等待+超时；install 保持幂等与主队列断言
- [x] 1.3 修改 `Sources/ALLaunchGuard/ALLaunchGuard.swift` 的 `activateSafeModeWindow()`：主线程同步调用 install，非主线程 dispatch main（保证 didFinishLaunching 首行调用时观察者先于 willConnect 注册）

## 2. 验证与复验

- [x] 2.1 swift test 全绿（46 存量 + 新增决策函数测试）；swift build 0 新增警告
- [x] 2.2 xcodebuild -scheme ALLaunchGuard iOS Simulator 构建 0 错误 0 警告
- [x] 2.3 MPLaunchExample 冒烟复验（scene 路径）：进入安全模式后窗口随 scene 连接/激活立即可见（截图，无 5 秒黑屏）
- [x] 2.4 BasicExample 冒烟复验（经典路径）：进入安全模式后窗口立即显示（截图，无 5 秒黑屏等待）
