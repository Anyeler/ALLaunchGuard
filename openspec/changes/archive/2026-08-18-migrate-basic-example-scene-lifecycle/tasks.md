# 任务：migrate-basic-example-scene-lifecycle

## 1. 代码迁移

- [x] 1.1 新增 `Examples/BasicExample/BasicExample/SceneDelegate.swift`：isInSafeMode 门控早退（安全模式不建 window，库独立窗口经 willConnect 观察者接管）+ UIWindow(windowScene:) 构建 UINavigationController(HomeViewController) + makeKeyAndVisible + DEBUG scheduleAutoCrashIfEnabled 调度（window 可见后）；中文注释锚定门控时序
- [x] 1.2 `Examples/BasicExample/BasicExample/AppDelegate.swift`：删除 window 属性（L7）、window 构建块（L58-66）、scheduleAutoCrashIfEnabled 调度（L68-74）；保留步骤 1/2/3（fixActions/safeModeLaunchTasks 注册 + start() 门控 + DEBUG disarm）；更新门控注释
- [x] 1.3 `Examples/BasicExample/BasicExample/Info.plist`：UIApplicationSupportsIndirectInputEvents 之后插入 UIApplicationSceneManifest（与 MPLaunchExample Info.plist L27-43 逐字一致）
- [x] 1.4 `Examples/BasicExample/BasicExample.xcodeproj/project.pbxproj`：SceneDelegate.swift 四处登记（PBXBuildFile/PBXFileReference/PBXGroup children/PBXSourcesBuildPhase），沿用现有 ID 规律，先 grep 确认唯一
- [x] 1.5 注释同步：HomeViewController.swift 类注释（L6-7，"AppDelegate 直接 return" → "SceneDelegate 以 isInSafeMode 门控"）；CrashSimulator.swift 类注释调度位置描述（SceneDelegate window 可见后调度）

## 2. 文档

- [x] 2.1 `README.md` L637：「经典 AppDelegate 生命周期（无 SceneDelegate）」改为 SceneDelegate 生命周期描述（门控仍在 didFinishLaunching 首行，安全模式窗口经 willConnect 观察者挂载）

## 3. 验证（实际执行，不得推断）

- [x] 3.1 xcodebuild -project Examples/BasicExample/BasicExample.xcodeproj -scheme BasicExample -destination 'generic/platform=iOS Simulator' build：0 错误 0 警告（BUILD SUCCEEDED，grep warning:/error: 无匹配）
- [x] 3.2 iOS 26 模拟器启动：确认控制台不再出现 "UIScene lifecycle will soon be required" 警告（iPhone 17 Pro / iOS 26.5，--console-pty 启动日志与 log show --last 2m 均为 0 匹配）
- [x] 3.3 冒烟闭环：正常启动首页可见（/tmp/ag-scene-normal.png）→ PlistBuddy 注入 autoCrashRemaining=3 → 两次自动崩溃（SIGTRAP 崩溃报告 091110/091132）→ 第三次安全模式菜单页可见（waitScene 路径，/tmp/ag-scene-safemode.png）→ 粘滞注入冷启动窗口可见（/tmp/ag-scene-sticky.png）→ DEBUG 直入：本会话纯 headless（CGWindowList 确认窗口服务器无 Simulator 窗口，kill+boot+Window 菜单唤起均无效），坐标点击不可行，按预案以粘滞路径证据替代；修复重启 UI 点击同理不可行，以磁盘状态模拟 reset 等效替代：一次性横幅出现（/tmp/ag-scene-banner.png）、再次启动不重复（/tmp/ag-scene-nobanner.png）；冒烟后已 uninstall 清理
- [x] 3.4 swift test 回归（库零改动，65 全绿基线，Executed 65 tests, 0 failures）

## 4. 收口（编排层处理）

- [x] 4.1 归档变更；提交（fix(example) 语义）；推送分支；创建 PR（base: main）；推送前安全扫描门禁（额度耗尽，用户此前已确认跳过）
