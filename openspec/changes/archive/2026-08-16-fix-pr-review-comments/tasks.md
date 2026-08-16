# 任务：fix-pr-review-comments

- [x] 1.1 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeWindow.swift`：install() 的 `dispatchPrecondition(condition: .onQueue(.main))` 替换为 `assert(Thread.isMainThread, "安全模式窗口安装必须在主线程执行")`，注释说明 Debug 断言/Release 容忍策略与防御意图
- [x] 1.2 `Examples/BasicExample/BasicExample/AppDelegate.swift`：`window.rootViewController = HomeViewController()` 改为 `UINavigationController(rootViewController: HomeViewController())`；核对 HomeViewController 布局约束使用 safeAreaLayoutGuide（不受导航栏影响），如用绝对 top 约束则同步修正
- [x] 1.3 验证：swift test 50 全绿；swift build 0 新增警告；xcodebuild 库 iOS Simulator 构建（独立 derivedDataPath）0 错误 0 警告；BasicExample 构建通过 + 模拟器冒烟截图（/tmp 新路径：首页导航栏 + 右上角"直接进入安全模式"入口可见）
