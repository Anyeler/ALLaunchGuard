# 设计：add-example-apps

## Context

库已完成 2.0 功能：start() 状态机返回 Bool、fixActions + perform 编排、菜单页、独立 UIWindow 接管（presentationStyle 默认 dedicatedWindow）、DEBUG enterSafeModeForTesting。mplaunch 仓库（/Users/zhangyuanwen/Projects/MyProjects/mplaunch）已支持 SPM（Package.swift + 2 个 import 修复，macOS/iOS Simulator 双目标编译通过），其 API：Launchable 协议（syncTask/asyncTask/dependencies/appDelegate/sceneDelegate）、Launchers 扩展 @objc 属性注册、LaunchSession.shared.onceUponAnApp/onceUponAScene、LaunchDependancyInjector（ldi 属性注入依赖表）。Example 目录工程内不放 Package.swift（避免 SwiftPM 目录歧义）；podspec glob 与主 Package.swift 均不涉及 Examples。

## Goals / Non-Goals

**Goals:**
- 两个可运行的 iOS App 示例：BasicExample（公开、通用门控范式）与 MPLaunchExample（本地生成、编排器门控范式）。
- README 2.0 全面重写 + podspec 2.0.0 + .gitignore 收口。
- 以 Example 为载体完成模拟器端到端冒烟。

**Non-Goals:**
- Example 上 App Store/签名配置、多语言界面、UI 精细美化（够用即可）。
- CI 集成、Example 的单元测试。
- MPLaunchExample 进 git（内部私有库）。

## Decisions

### D1. Example 工程生成方式：手工最小 xcodeproj（非 xcodegen/tuist）
BasicExample 生成最小可用的 project.pbxproj（App target + 本地包引用 ../../ Package.swift + iOS 14+ deployment target），提交进 git。备选 xcodegen（project.yml 生成）被否决：引入额外工具链依赖；手工工程一次成型后维护成本低。xcodeproj 可由实施代理用 Xcode MCP 或脚本模板构建——**实施注意**：若手工 pbxproj 复杂度过高，允许退化为提供 `project.yml` + 生成说明，但优先完整工程。

### D2. BasicExample 结构
AppDelegate 生命周期（无 SceneDelegate，走库窗口接管的最简路径验证经典 delegate 分支）：didFinishLaunching 首行 `fixActions = [内置清缓存, 自定义示例动作]` → `if start() { return true }` → 正常构建 window + 首页 VC。首页：启动任务清单（静态列表模拟，安全模式启动时此代码不执行）、"模拟启动闪退"按钮（fatalError）、DEBUG 工具页（"直接进入安全模式"按钮调 enterSafeModeForTesting 后提示重启）。自定义动作示例：清理示例沙盒自定义目录（演示 FixAction 协议实现）。

### D3. MPLaunchExample 整目录不进 git（递从用户明确要求）
用户明确要求 MPLaunch 示例 App 不给 git 追踪（内部私有库相关）。处理：**Examples/MPLaunchExample/ 整目录加入 .gitignore**，文件仅存于本地供本机演示与验证；主 README Examples 指引中说明该示例为本地专属（依赖内部 mplaunch 仓库）不入库、并给出从零搭建同类示例的关键步骤描述（门控代码范式在 README 专节已完整可复制）。不提供自动生成脚本（路径因人而异且脚本生成 pbxproj 脆弱），本地示例内附一个简短 LOCAL_README 说明双本地包引用方式（根 ALLaunchGuard 包 + ../mplaunch 包）。

### D4. MPLaunchExample 集成形态（NIO 风格演示）
AppDelegate：didFinishLaunching 首行 fixActions → `if ALLaunchGuard.shared.start() { return true }` → `try LaunchSession.shared.onceUponAnApp(...)`。SceneDelegate：`scene(willConnectTo:)` 中安全模式（读 shouldEnterSafeMode）时直接 return 跳过 onceUponAScene。示例模块：3 个 Launchable（如 NetworkModule → DatabaseModule → UIModule 依赖链，UIModule.sceneDelegate 构建 root VC）。首页展示模块执行状态清单（静态记录）。

### D5. README 结构
安装（SPM/CocoaPods 2.0.0）→ Quick Start（门控范式完整代码）→ How It Works（打点法状态机图示文字版 + 清零条件表）→ 配置表（全部属性含默认值）→ FixAction 自定义指南 → 与启动编排器集成（MPLaunch 专节，门控代码）→ Examples 指引 → Migration to 2.0（fixButtonTitle→restartHint、旧 VC deprecated、默认窗口接管行为变化、5 秒自动清零语义）→ License。

### D6. 版本与收口顺序
先 Examples 构建通过 → 模拟器冒烟 → README/podspec/.gitignore/Config.message 文案 → swift test 回归（Config 默认文案变化可能影响测试断言，同步迁移）→ 归档。不执行 pod trunk push / git tag（AGENTS.md 硬约束）。

## Risks / Trade-offs

- [手工 pbxproj 易错] → 优先 Xcode MCP 工具辅助；构建验证兜底；D1 备选退化路径。
- [MPLaunch 本地路径因人而异] → setup 校验 + 明确 README 指引；构建验证在本机路径完成。
- [模拟器端到端冒烟耗时（多次崩溃重启）] → 用 DEBUG 直接进入安全模式入口缩短路径；完整 3 次闪退链路至少跑一遍。
- [Config.message 文案变化影响既有断言] → 先查测试引用再改，同步迁移。

## Migration Plan

按 D6 顺序执行；全部通过后归档本变更，仓库形成完整 2.0 待发布状态（提交与 tag 由用户决定）。

## Open Questions

（无。）
