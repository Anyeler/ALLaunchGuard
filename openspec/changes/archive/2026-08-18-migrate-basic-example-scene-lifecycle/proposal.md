# 提案：migrate-basic-example-scene-lifecycle

## Why

BasicExample 在 iOS 26 模拟器运行时控制台出现警告 "UIScene lifecycle will soon be required. Failure to adopt will result in an assert in the future."——根因是 Info.plist 无 UIApplicationSceneManifest（经典 AppDelegate 生命周期）。iOS 未来 SDK 将该警告升级为启动失败，需正式采纳 Scene 生命周期消除警告，同时与 MPLaunchExample 的生命周期形态对齐（两个示例互为对照）。官方依据：TN3187: Migrating to the UIKit scene-based life cycle（iOS 26 起输出该警告，iOS 26 之后下一个大版本用最新 SDK 构建时为强制要求）。

## What Changes

- BasicExample 迁移到 SceneDelegate 生命周期：
  - Info.plist 增加 UIApplicationSceneManifest（与 MPLaunchExample 逐字一致的已验证形态：UIApplicationSupportsMultipleScenes=false + UISceneConfigurations 指向 $(PRODUCT_MODULE_NAME).SceneDelegate）。
  - 新增 SceneDelegate.swift：scene(_:willConnectTo:) 内 isInSafeMode 门控早退 + UIWindow(windowScene:) 构建 UINavigationController(HomeViewController) + CrashSimulator 调度随 window 可见点迁入。
  - AppDelegate 精简：删除 window 属性与 window 构建/崩溃调度（迁至 SceneDelegate），保留 fixActions/safeModeLaunchTasks 注册与 start() 门控。
  - project.pbxproj 四处登记新文件；README L637 生命周期描述同步；HomeViewController/CrashSimulator 注释同步。
- 库源码零改动：manifest 检测为运行时读宿主 Bundle（ALLaunchGuardSafeModeWindow.swift L61-63），加 manifest 后窗口挂载分流自动从 immediateFrameFallback 切换到已被 MPLaunchExample 冒烟验证的 waitSceneWithTimeout 路径。
- 不触碰 Sources/、Tests/、podspec、Package.swift。

## Capabilities

（skip_specs：生命周期形态变化不触及 example-apps spec 的行为契约——主 spec 的"通用示例 App"需求全部 SHALL 子句为行为契约、不含生命周期形态描述；无 delta 变更有仓库先例。）

## Impact

- Examples/BasicExample/：Info.plist、AppDelegate.swift、新增 SceneDelegate.swift、project.pbxproj；HomeViewController.swift 与 CrashSimulator.swift 仅注释同步。
- README.md 一行描述同步。
- 演示行为契约全部保持不变（门控/fixActions/safeModeLaunchTasks/连续闪退闭环/一次性横幅/DEBUG 直入）。
