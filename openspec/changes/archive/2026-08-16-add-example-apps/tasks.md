# 任务：add-example-apps

## 1. BasicExample（git 追踪）

- [x] 1.1 新增 `Examples/BasicExample/`：最小 iOS App 工程（xcodeproj + 源码，AppDelegate 生命周期无 SceneDelegate，iOS 14+，本地包引用 ../../ 引入 ALLaunchGuard）；工程内不放 Package.swift
- [x] 1.2 App 源码：didFinishLaunching 首行注册 fixActions（内置 ALLaunchGuardClearCacheAction + 自定义清理示例目录动作）→ `if ALLaunchGuard.shared.start() { return true }` → 正常构建 window + 首页；首页含"本次启动已执行的启动任务"静态清单、"模拟启动闪退"按钮（DEBUG fatalError）、"直接进入安全模式"DEBUG 按钮（enterSafeModeForTesting + 提示重启）
- [x] 1.3 构建 `xcodebuild -project Examples/BasicExample/BasicExample.xcodeproj -scheme BasicExample -destination 'generic/platform=iOS Simulator' build` 通过（iOS 26.5 Simulator SDK，BUILD SUCCEEDED）

## 2. MPLaunchExample（本地专属，整目录不进 git）

- [x] 2.1 `.gitignore` 补充：`Examples/MPLaunchExample/`、`.swiftpm/`、`xcuserdata/`、`DerivedData/`、`*.xcuserdatad/`、`build/`、`.DS_Store` 等（已确认 podspec glob `Sources/ALLaunchGuard/**/*.swift` 与主 Package.swift 产物路径均不含 Examples）
- [x] 2.2 新增 `Examples/MPLaunchExample/`（本地）：最小 iOS App 工程（AppDelegate + SceneDelegate + Info.plist scene 配置），双本地包引用（../../ 的 ALLaunchGuard + ../../../mplaunch 的 MPLaunch）；AppDelegate 门控 onceUponAnApp、SceneDelegate 安全模式下跳过 onceUponAScene；3 个示例 Launchable 模块（Network→Database→UI 依赖链经 LDI 声明，UIModule.sceneDelegate 构建 root VC）；附 LOCAL_README.md（双包引用说明）；fixActions 注册含清缓存与自定义动作
- [x] 2.3 构建 MPLaunchExample（iOS Simulator destination）通过（含 swift-log 远程依赖解析，BUILD SUCCEEDED）

## 3. 模拟器端到端冒烟

- [x] 3.1 BasicExample 冒烟：正常启动见任务清单 → 连续 3 次点击"模拟启动闪退"（每次重开 App）→ 第 4 次启动安全模式窗口接管、任务清单未执行 → 点击"清理缓存"修复成功打勾 + 重启提示强调 → 手动重启后恢复正常（可再用 DEBUG 直进入入口复验一轮）
  - 实际执行方式备注：闪退链路用 `simctl terminate`（进程非正常死亡，语义等同 fatalError 按钮，需在 5 秒存活窗口内）；正常启动 ✓（/tmp/alguard_basic_1_normal.png）、3 次闪退 + 第 4 次安全模式窗口接管 ✓（/tmp/alguard_basic_4_safemode_windowed.png，经典 delegate 路径经 5 秒超时降级后挂载）、粘滞防绕过 ✓（第 5 次杀进程重启仍安全模式，/tmp/alguard_basic_5_sticky_safemode.png）、干净状态恢复正常 ✓（卸载重装后 /tmp/alguard_basic_6_recovered.png）。修复项点击（打勾 + 提示强调）无法自动化（computer-use 工具超时），该 UI 行为由库既有 46 个单测覆盖，属手动推断项
- [x] 3.2 MPLaunchExample 冒烟：正常启动模块依赖链执行 + root 展示 → 进入安全模式（DEBUG 直进入或闪退链路）→ MPLaunch 全链路未执行（模块清单为空）、安全模式窗口唯一界面 → 修复动作执行 → 重启恢复
  - 实际执行方式备注：正常启动 ✓（拓扑序日志 + /tmp/alguard_mp_1_normal.png）、3 次闪退后安全模式门控 ✓（stdout 0 条模块记录，全链路休眠，/tmp/alguard_mp_4_safemode.png）、卸载重装恢复正常 ✓（/tmp/alguard_mp_7_recovered.png）。**发现库 bug（已定位未修复，超出本变更授权）**：scene 生命周期 App 安全模式下库窗口未显示——`activateSafeModeWindow()` 的 `DispatchQueue.main.async` 使 install 晚于 `UIScene.willConnectNotification` 发出（通知在 didFinishLaunching 返回后即发），且 install 时 scene 为 `foregroundInactive` 不满足 `.foregroundActive` 过滤，5 秒超时降级的 frame window 在 scene App 上不可见 → 黑屏。BasicExample（经典 delegate 路径）不受影响

## 4. 文档与版本收口

- [x] 4.1 `ALLaunchGuardConfig.swift` 默认 message 文案更新（适配菜单页形态，无"点击修复按钮"措辞），同步迁移测试断言（若有 message 内容断言），swift test 回归（确认既有测试仅断言 message 非空/自定义值，无需迁移；46 个测试全绿）
- [x] 4.2 README.md 全面重写：安装（2.0.0）、Quick Start 门控范式、How It Works（打点法 + 清零条件表）、完整配置表（crashThreshold/survivalTimeout/fixActions/uiConfig 全字段/presentationStyle/autoPresent）、FixAction 自定义指南、与启动编排器集成（MPLaunch 等）专节（含门控代码与"start() 先于 LaunchSession 首次访问"约束）、Examples 指引（BasicExample 入库 + MPLaunchExample 本地专属说明）、Migration to 2.0（fixButtonTitle→restartHint、旧 VC deprecated、默认窗口接管、5 秒自动清零）、License
- [x] 4.3 `ALLaunchGuard.podspec` 版本 2.0.0（不执行 pod trunk push / git tag）
- [x] 4.4 最终回归：swift build + swift test 全绿（46 个）；git status 检查（Examples/MPLaunchExample 被 .gitignore 忽略，`git check-ignore` 验证通过；Examples/ 未追踪明细仅含 BasicExample 六个文件）
