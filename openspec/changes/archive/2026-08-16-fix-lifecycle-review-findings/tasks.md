# 任务：fix-lifecycle-review-findings

## 1. 断言与线程契约（P1①）

- [x] 1.1 修改 `Sources/ALLaunchGuard/ALLaunchGuard.swift`：`start()` 的 `dispatchPrecondition(condition: .onQueue(.main))` 替换为 `assert(Thread.isMainThread, "ALLaunchGuard.start() 必须在主线程调用")`，修正 doc comment（如实说明：Debug 断言暴露误用、Release 容忍；didFinishLaunching 首行天然满足）
- [x] 1.2 `markLaunchSuccessful()` 与 `reset()` 补 `assert(Thread.isMainThread, ...)` 与 doc comment 主线程契约（说明 perform 编排层内部已在主队列调用 reset，宿主直调也应主线程）

## 2. scene 断连自愈（P1②）

- [x] 2.1 修改 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`：`handleSceneWillConnect` 分支①（已挂 scene）改为直接 return 不再调用 cleanupMountWaiters；观察者清理仅保留于 deinit（与超时任务取消）；确认分支②（windowScene == nil 或 window == nil）覆盖"断连后旧窗重连"路径（以新 scene 重建、迁移 root、废弃旧窗、makeKeyAndVisible）；注释说明观察者持续保持的设计意图与官方断连语义依据
- [x] 2.2 `UIScreen.main.bounds` 两处使用点加弃用锚定注释（iOS 26.0 起弃用、仅无 scene 兜底路径、正常路径 UIWindow(windowScene:)）

## 3. README 补齐

- [x] 3.1 新增"已知限制"小节：iOS 15/16 预热 bug 场景（偶发执行 didFinishLaunching → 预热回收计为一次闪退；连续 3 个预热-回收周期才可能误触发；真实启动存活 5 秒自然复位；iOS 17+ 官方语义无此风险）
- [x] 3.2 新增 SwiftUI 接入小节：App.init（主线程、先于 didFinishLaunching）注册 fixActions + start() 门控/shouldEnterSafeMode 分流 body 的范式代码与 UIApplicationDelegateAdaptor 说明
- [x] 3.3 线程契约说明：start / markLaunchSuccessful / reset 须主线程调用（Debug 断言、Release 容忍）

## 4. 验证

- [x] 4.1 swift test 全绿（50 个）；swift build 0 新增警告
- [x] 4.2 xcodebuild -scheme ALLaunchGuard -destination 'generic/platform=iOS Simulator'（独立 derivedDataPath）0 错误 0 警告
- [x] 4.3 BasicExample 快速冒烟：正常启动 + 进入安全模式菜单页两态截图（/tmp 新路径），确认无回归
