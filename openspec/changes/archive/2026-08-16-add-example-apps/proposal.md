# 提案：add-example-apps

## Why

四个功能变更已完成（判定核心、修复动作、菜单 UI、窗口接管），需要：接入范例方便宿主开发者理解门控范式与看效果（含端到端冒烟验证载体）；README 全面重写以反映 2.0 API 与行为变化（fixButtonTitle 移除、presentationStyle 默认窗口接管、MPLaunch 门控专节）；版本收口 2.0.0。用户明确要求两个 Example：通用示例（git 追踪）与 MPLaunch 集成示例（内部私有库，不进 git）。

## What Changes

- 新增 `Examples/BasicExample/`（git 追踪）：Xcode 工程 + 本地 SPM 包引用根目录 ALLaunchGuard；首页展示"本次启动已执行的正常启动任务"清单（安全模式下为空、显示安全模式页）；"模拟启动闪退"按钮（fatalError，连按 3 次触发）；DEBUG"直接进入安全模式"入口（enterSafeModeForTesting）；注册内置清缓存 + 自定义修复动作。
- 新增 `Examples/MPLaunchExample/`（**不进 git**，.gitignore 整目录忽略）：真实 MPLaunch 编排（示例 Launchable 模块、root VC 构建放入模块 sceneDelegate、NIO 风格）；AppDelegate 门控 onceUponAnApp、SceneDelegate 门控 onceUponAScene；附 setup 脚本/说明（从本地 ../mplaunch 仓库引用本地包）。
- README 重写：新接入范式（didFinishLaunching 首行门控）、How It Works 打点法语义、配置表（survivalTimeout/crashThreshold/fixActions/restartHint/presentationStyle/autoPresent）、deprecated 标注（fixButtonTitle 迁移、旧 VC、presentSafeModeUIIfNeeded）、与启动编排器集成（MPLaunch 等）专节、Examples 使用指引、2.0 迁移说明。
- `ALLaunchGuard.podspec` 版本 2.0.0（不执行 pod trunk push / git tag）；`.gitignore` 补充（Examples/MPLaunchExample/、.swiftpm/、xcuserdata、DerivedData）。
- 顺带：Config.message 默认文案更新为适配菜单页形态（无"点击修复按钮"措辞）。

## Capabilities

### New Capabilities

- `example-apps`：接入范例能力——通用示例与 MPLaunch 编排示例的行为契约（演示正常/安全模式两态、模拟闪退触发、门控范式示范、MPLaunch 全链路休眠演示）。

### Modified Capabilities

（无——三个功能主 spec 需求不变；README/版本/podspec 属文档与发布物。）

## Impact

- 新增 Examples/ 目录（两个 App 工程）；修改 README.md、ALLaunchGuard.podspec、.gitignore、ALLaunchGuardConfig.swift（仅默认文案）。
- 验证：两个 Example 的 iOS Simulator 构建通过 + 端到端模拟器冒烟（正常启动 → 3 次闪退 → 窗口接管 → 修复 → 重启恢复）。
- Example 不进库产物（podspec glob 与主 Package.swift 均不含 Examples）。
