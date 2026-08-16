# ALLaunchGuard

[![Swift 5.0+](https://img.shields.io/badge/Swift-5.0%2B-orange)](https://swift.org)
[![iOS 14.0+](https://img.shields.io/badge/iOS-14.0%2B-blue)](https://developer.apple.com/ios/)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)
[![CocoaPods compatible](https://img.shields.io/badge/CocoaPods-compatible-brightgreen)](https://cocoapods.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

ALLaunchGuard 是一个 iOS 启动安全模式库：通过**打点法**（预支计数 + 存活确认）检测
**连续启动闪退**（crash loop），达到阈值后进入**安全模式**——宿主跳过全部启动任务，
由独立 UIWindow 接管的**菜单式修复页**成为唯一界面，用户选择修复项恢复应用。

- 判定核心：`start()` 状态机返回 `Bool`（进入安全模式返回 `true`）
- 修复编排：`fixActions: [ALLaunchGuardFixAction]` 菜单数据源 + `perform(_:completion:)` 统一编排
- 界面接管：`presentationStyle` 默认 `.dedicatedWindow`（独立 UIWindow，不依赖宿主是否构建界面）
- 内置动作：清缓存（`ALLaunchGuardClearCacheAction`）与闭包包装（`ALLaunchGuardClosureAction`）
- 生命周期回调：`ALLaunchGuardDelegate`（进入 / 退出 / 修复完成）

---

## 环境要求

| 平台 | 最低版本 |
|------|----------|
| iOS  | 14.0     |
| Swift | 5.0     |

---

## 安装

### Swift Package Manager

在 `Package.swift` 中添加：

```swift
dependencies: [
    .package(url: "https://github.com/Anyeler/ALLaunchGuard.git", from: "2.0.0")
]
```

或在 Xcode 中：**File → Add Package Dependencies…** 输入仓库地址。

### CocoaPods

```ruby
pod 'ALLaunchGuard', '~> 2.0'
```

然后执行 `pod install`。

---

## Quick Start：门控范式

核心接入范式只有三步，全部发生在 `application(_:didFinishLaunchingWithOptions:)`
**首行**（安全模式分支必须先于一切启动任务）：

```swift
import ALLaunchGuard

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. 注册修复动作（必须在 start() 之前——安全模式菜单的数据源）
        ALLaunchGuard.shared.fixActions = [
            ALLaunchGuardClearCacheAction(),                    // 内置：清沙盒 Caches
            ALLaunchGuardClosureAction(title: "重置用户配置") { completion in
                MyConfigCenter.reset { completion(true) }        // 自定义：闭包包装
            }
        ]

        // 2. 安全模式门控：返回 true 表示本次处于安全模式，
        //    跳过全部正常启动任务（不构建 window / 首页）。
        //    修复菜单页由库以独立 UIWindow 自动接管展示。
        if ALLaunchGuard.shared.start() {
            return true
        }

        // 3. 正常启动：构建 window 与首页（安全模式下不会执行到这里）
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = HomeViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
```

安全模式菜单页效果：警示图标 + 标题/正文 + 修复项列表（点击执行：成功打勾、
失败可重试）+ 底部常驻重启提示（任一修复成功后强调展示，并在 `allowRestartExit`
允许时同步出现“重启应用”按钮：点击后经系统 Alert 二次确认终止进程，
下次冷启动恢复正常流程）。页面不会自动关闭，等待用户重启应用。

### 可选：监听安全模式生命周期

```swift
ALLaunchGuard.shared.delegate = self

extension AppDelegate: ALLaunchGuardDelegate {
    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {
        // 埋点、日志
    }

    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard) {
        // 修复成功后触发（reset()）
    }

    func launchGuard(
        _ launchGuard: ALLaunchGuard,
        didFinishFixAction action: ALLaunchGuardFixAction,
        success: Bool
    ) {
        // 单个修复动作完成（success 为 false 时安全模式保持激活，允许重试）
    }
}
```

### 可选：极早期无副作用查询

```swift
// 可在 start() 之前调用，不改变任何存储状态
if ALLaunchGuard.shared.shouldEnterSafeMode {
    // 极早期分流（如跳过第三方 SDK 初始化）
}
```

### 可选：DEBUG 直进入入口

```swift
#if DEBUG
// 测试/演示用：强制激活安全模式并持久化（Release 构建不存在该 API）
ALLaunchGuard.shared.enterSafeModeForTesting()
#endif
```

---

## How It Works：打点法判定语义

每次 `start()` 执行如下状态机：

```
启动 → start()
  │
  ├─ ① 裁决上一会话残留
  │     ├─ 粘滞安全模式标记（safeModeActive）──────→ 直接激活安全模式（不递增计数、不计时）
  │     ├─ 上次已进入后台（系统回收/上滑强杀/OOM）→ 清零计数
  │     └─ 上次打点 uptime > 本次 systemUptime（设备重启）→ 清零计数
  │
  ├─ ② 预支递增计数（+1），写入本次启动 uptime 打点，清除后台标记
  │
  ├─ ③ 计数 ≥ crashThreshold ──→ 持久化粘滞标记，激活安全模式（返回 true）
  │
  └─ ④ 未触发 → 启动存活计时（survivalTimeout 秒），到期自动清零计数
```

**"预支计数 + 存活确认"**：先假设每次启动都是闪退（+1），进程存活满
`survivalTimeout` 秒即证伪（清零）。主线程 hang 时确认永不发生，看门狗语义正确。

**计数清零条件一览**：

| 条件 | 说明 |
|------|------|
| 存活满 `survivalTimeout` 秒 | 默认 5 秒，自动清零（会话代际 + 打点双重校验防误清） |
| 调用 `markLaunchSuccessful()` | 与存活计时幂等共存，可提前确认；仅清零计数，不退出安全模式 |
| 上次会话进入过后台（didEnterBackground） | 持久化后台标记，下次启动清零计数（系统回收 / 上滑强杀后台 / 后台 OOM 不计为闪退）。**边界**：进后台后回前台 5 秒内崩溃会计漏一次——回前台不重置计时也不清标记，属“宁漏报不误报”取舍 |
| 检测到设备重启 | 单调时钟（systemUptime）打点比较，不受改时间影响 |
| 应用正常终止（willTerminate） | 兜底清零 |
| 修复动作成功 | `perform(_:completion:)` 编排触发一次 `reset()` |

**粘滞安全模式**：激活标记持久化，杀进程重启无法绕过；唯一的退出路径是修复
动作成功（自动 `reset()`）或手动调用 `reset()`。

### 已知限制：iOS 15/16 预热（prewarming）bug 盲区

iOS 15/16 存在预热执行 bug：系统预热启动偶发会执行到 `didFinishLaunching`
（官方语义下预热不应执行任何 app 代码）。此时 `start()` 已预支递增计数，
而预热进程被系统回收时未进入过后台（`didEnterBackground` 未触发），
该次预热回收会计漏为一次"启动闪退"：

- **误触发条件苛刻**：需连续 3 个"预热 → 回收"周期（默认阈值 3），且
  期间无任何一次真实启动——真实启动存活满 5 秒即自然复位计数；
- **自然复位**：任何一次真实启动存活满 `survivalTimeout`（默认 5 秒），
  计数自动清零，预热残留计数不会永久累积；
- **iOS 17+**：官方修复了该 bug（预热不执行 `didFinishLaunching`），
  无此风险；iOS 14 及以下预热不执行 app 代码，同样无此风险。

---

## 配置

### 守护行为（`ALLaunchGuard.shared`）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `crashThreshold` | `Int` | `3` | 连续启动闪退次数阈值，达到即激活安全模式 |
| `survivalTimeout` | `TimeInterval` | `5` | 存活确认时长（秒），存活满该时长自动清零计数 |
| `fixActions` | `[ALLaunchGuardFixAction]` | `[]` | 安全模式菜单数据源，注册顺序即展示顺序 |
| `delegate` | `ALLaunchGuardDelegate?` | `nil` | 生命周期回调（进入 / 退出 / 修复完成） |
| `isInSafeMode` | `Bool` | `false` | 当前是否处于安全模式（只读） |
| `shouldEnterSafeMode` | `Bool` | — | 极早期无副作用查询（start() 前可用） |

### 界面配置（`ALLaunchGuardConfig` / `uiConfig`）

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `title` | `String` | `"应用启动异常"` | 菜单页大标题 |
| `message` | `String` | *(见下方默认值)* | 标题下方正文 |
| `restartHint` | `String` | `"修复完成后，请退出应用重新打开"` | 底部常驻重启提示；任一修复成功后强调展示 |
| `restartButtonTitle` | `String` | `"重启应用"` | 修复成功后展示的一键重启按钮文案（见下方 exit(0) 审核说明） |
| `allowRestartExit` | `Bool` | `true` | 是否允许修复成功后展示“重启应用”按钮；置 `false` 恒不展示，回退纯文字提示旧行为 |
| `tintColor` | `UIColor` | `.systemOrange` | 图标 / 强调色 |
| `autoPresent` | `Bool` | `true` | 安全模式激活时是否自动展示界面 |
| `presentationStyle` | `ALLaunchGuardPresentationStyle` | `.dedicatedWindow` | 自动展示样式（见下） |

`message` 默认值：

```
检测到应用连续启动异常，已进入安全模式。
请在下方选择修复项进行修复，完成后重启应用。
```

`presentationStyle` 取值：

| 样式 | 行为 |
|------|------|
| `.dedicatedWindow`（默认） | 独立 UIWindow 接管：不依赖宿主是否构建 window/rootVC，宿主漏分流时因更高 windowLevel 形成覆盖兜底 |
| `.presentOnRoot` | 旧版兼容：在宿主 key window rootVC 上 present（宿主必须已构建界面） |

配置示例：

```swift
var config = ALLaunchGuardConfig()
config.title = "启动出现问题"
config.message = "应用连续多次启动异常，已进入安全模式。"
config.restartHint = "修复完成后请重启应用"
config.restartButtonTitle = "重启应用"        // 默认值；一键重启按钮文案
config.allowRestartExit = true                 // 默认值；false 隐藏按钮回退纯提示
config.tintColor = .systemRed
config.autoPresent = true                     // 默认即 true
config.presentationStyle = .dedicatedWindow   // 默认即窗口接管
ALLaunchGuard.shared.uiConfig = config
ALLaunchGuard.shared.start()
```

#### exit(0) 与 App Store 审核（allowRestartExit）

修复成功后的“重启应用”按钮通过 `exit(0)` 终止进程——iOS 不存在真正的
热重启，业界安全模式实现（如微信“重启微信”）均为终止进程方案，多数
大厂安全模式均有此先例，风险较低。但主动退出 API 历来存在审核争议，
审核敏感的宿主可置 `allowRestartExit = false` 隐藏按钮，回退纯文字
提示旧行为。行为约束（两种配置下均成立）：

- 未修复成功前按钮恒不展示（此时重启会再次进入安全模式，无意义且误导）；
- 点击后必弹系统 Alert 二次确认才终止进程（防误触，亦为宿主可感知的行为锚点）；
- 修复流程本身不会自动关闭页面或自动调用 exit——重启决策始终交给用户。

`autoPresent = false` 时，安全模式激活后不展示任何界面，宿主可自行调用
`activateSafeModeWindow()`（窗口接管）或 `presentSafeModeMenu()`（present 路径）。

---

## FixAction：自定义修复动作

修复动作是安全模式菜单的菜单项（class 协议，动作被强持有至单例生命周期）：

```swift
public protocol ALLaunchGuardFixAction: AnyObject {
    var title: String { get }             // 菜单标题
    var iconSystemName: String? { get }   // SF Symbol 图标（nil 用默认图标）
    var isDestructive: Bool { get }       // 破坏性样式（红色警示），默认 false
    func perform(completion: @escaping (Bool) -> Void)
    // 实现方保证 completion 恰好回调一次：true 成功 / false 失败
}
```

完整自定义示例：

```swift
final class ClearDemoDataAction: ALLaunchGuardFixAction {
    let title = "清除示例数据"
    let iconSystemName = "folder.badge.trash"

    func perform(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 耗时 IO 建议后台执行；completion 可在任意线程回调
            do {
                try Self.removeDemoData()
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}
```

**执行编排语义**（`ALLaunchGuard.perform(_:completion:)`，菜单页点击菜单项即走此入口）：

- 成功 → 触发一次 `reset()`（幂等：清零计数、清除粘滞标记、触发退出回调）；
- 失败 → 不改动任何安全模式状态（允许用户重试）；
- 菜单页 UI 反馈：成功打勾置灰不可再点 / 失败红色警示可重试 / 执行中整表禁交互。

轻量场景可直接使用内置包装：

```swift
ALLaunchGuard.shared.fixActions = [
    ALLaunchGuardClearCacheAction(),  // 内置：清沙盒 Caches 目录（含子目录）
    ALLaunchGuardClosureAction(title: "重置账号", iconSystemName: "person.crop.circle.badge.xmark") { completion in
        MyAccountCenter.reset { completion(true) }
    }
]
```

空列表兜底：若 `fixActions` 为空（宿主忘记注册或升级残留计数首启触发），
菜单页会自动注入内置 `ALLaunchGuardResetSafeModeAction`（“重置安全模式”，
破坏性样式，执行后 reset 退出安全模式），保证安全模式始终存在用户
出口——但仍推荐注册业务修复动作，兜底仅供异常场景。

---

## 自定义存储（`ALLaunchGuardStorage`）

`ALLaunchGuard` 通过 `ALLaunchGuardStorage` 协议解耦持久化（默认实现
`UserDefaultsLaunchGuardStorage`，写 `UserDefaults.standard`），可注入
Keychain / 文件 / 数据库等宿主后端：

```swift
public protocol ALLaunchGuardStorage: AnyObject {
    var consecutiveCrashCount: Int { get set }           // 连续闪退计数（1.x 即有）
    var lastLaunchMarkUptime: TimeInterval? { get set }  // 上次启动 uptime 打点（2.0 新增）
    var lastLaunchDiedInBackground: Bool { get set }     // 上次会话是否进过后台（2.0 新增）
    var safeModeActive: Bool { get set }                 // 安全模式粘滞标记（2.0 新增）
}
```

### 向后兼容

2.0 新增的三个字段在协议扩展中提供了 no-op 默认实现（读取返回 `nil` /
`false`，写入被忽略）——只实现了 `consecutiveCrashCount` 的 1.x 自定义
存储**零改动即可编译**，判定降级为纯计数模式。

### 降级后果（no-op 字段未真正持久化时失去的防护）

| 未持久化字段 | 降级后果 |
|------|------|
| `safeModeActive` | **粘滞防护失效**：安全模式标记不跨启动保留，杀进程重启即可绕过安全模式（回到纯计数判定） |
| `lastLaunchDiedInBackground` | 后台死亡误判防护失效：系统回收 / 上滑强杀后台 / 后台 OOM 会被累计为闪退 |
| `lastLaunchMarkUptime` | 设备重启误判防护失效：重启导致的进程终止会被累计为闪退 |

### 1.x 自定义存储升级示例

补齐三个新字段即可恢复完整防护（以序列化写入宿主后端为例）：

```swift
final class KeychainLaunchGuardStorage: ALLaunchGuardStorage {
    var consecutiveCrashCount: Int = 0           { didSet { save() } }
    var lastLaunchMarkUptime: TimeInterval?      { didSet { save() } }
    var lastLaunchDiedInBackground: Bool = false { didSet { save() } }
    var safeModeActive: Bool = false             { didSet { save() } }

    private func save() { /* 序列化并写入宿主后端（Keychain / 文件 / DB） */ }
}

// didFinishLaunching 首行：注入自定义存储构建 guard（替代 .shared）
let launchGuard = ALLaunchGuard(storage: KeychainLaunchGuardStorage())
launchGuard.fixActions = [ /* ... */ ]
if launchGuard.start() { return true }
```

---

## 与启动编排器集成（MPLaunch 等）

若宿主使用 MPLaunch 之类的启动编排器（Launchable 模块拓扑执行），门控要点：
**`start()` 必须先于 `LaunchSession.shared` 的首次访问**，并分别在 AppDelegate /
SceneDelegate 两个编排入口处短路：

```swift
import ALLaunchGuard
import MPLaunch

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. 修复动作注册（首行）
        ALLaunchGuard.shared.fixActions = [
            ALLaunchGuardClearCacheAction(),
            /* ...自定义动作... */
        ]

        // 2. 门控：安全模式下跳过应用级编排，且不触碰 LaunchSession
        if ALLaunchGuard.shared.start() {
            return true
        }

        // 3. 正常启动：执行应用级编排
        try? LaunchSession.shared.onceUponAnApp(application, options: launchOptions)
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // 门控：安全模式下跳过 scene 级编排（root VC 构建等）
        if ALLaunchGuard.shared.isInSafeMode {
            return
        }
        try? LaunchSession.shared.onceUponAScene(scene, willConnectTo: session, options: connectionOptions)
    }
}
```

效果：安全模式下 MPLaunch **全链路休眠**（任何 Launchable 的 syncTask/asyncTask/
appDelegate/sceneDelegate 都不会执行），安全模式窗口为唯一界面。

其他启动编排器（或自研任务队列）同理：把"执行启动编排"整体放在 `start()`
返回 `false` 的分支内即可。

---

## SwiftUI 接入

SwiftUI 生命周期（`@main struct App`）下没有 `didFinishLaunching` 首行可放，
接入要点改到 `App.init`：

- `App.init` 在**主线程**执行，且**先于** `didFinishLaunching` 与首个
  `body` 求值——在 `init` 中注册 fixActions 并调用 `start()`，时序上
  天然满足"早于一切启动任务"的要求；
- `start()` 返回 `true`（或 `isInSafeMode`）时，`body` 中**不构建任何
  正常界面**（菜单式修复页已由库以独立 UIWindow 接管，无需宿主提供
  window / rootVC）；需要极早期分流（如跳过第三方 SDK 初始化）时可用
  `shouldEnterSafeMode`（无副作用查询，`start()` 前后均可调用）。

```swift
import SwiftUI
import ALLaunchGuard

@main
struct MyApp: App {
    // 可选：需要处理 push 等 UIApplicationDelegate 回调时桥接 AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // App.init（主线程、先于 didFinishLaunching）：注册修复动作 + 门控
        ALLaunchGuard.shared.fixActions = [
            ALLaunchGuardClearCacheAction(),
            ALLaunchGuardClosureAction(title: "重置用户配置") { completion in
                MyConfigCenter.reset { completion(true) }
            }
        ]
        if ALLaunchGuard.shared.start() {
            // 安全模式：跳过一切正常初始化（第三方 SDK、网络层等）
            return
        }
        // 正常启动：此处可做轻量初始化（耗时任务建议延后到首帧后）
    }

    var body: some Scene {
        WindowGroup {
            if ALLaunchGuard.shared.isInSafeMode {
                // 安全模式：修复页由库以独立 UIWindow 接管，
                // 这里只给空占位（不构建正常界面）
                EmptyView()
            } else {
                ContentView()
            }
        }
    }
}
```

注意：桥接的 `AppDelegate.didFinishLaunching` 仍会被调用（时序在
`App.init` 之后），若其中有启动任务，同样需要 `isInSafeMode` 门控短路。

---

## 线程契约

`start()` / `markLaunchSuccessful()` / `reset()` 必须在**主线程**调用
（`didFinishLaunching` 首行 / `App.init` 调用天然满足；
`perform(_:completion:)` 编排层内部已在主队列调用 `reset()`，宿主直调
也应保证主线程）：

- **Debug 构建**：违反将以断言暴露（`assert(Thread.isMainThread)`）；
- **Release 构建**：容忍，不崩溃——防闪退库不应在宿主误用时制造新的
  崩溃面，但后台线程调用存在存储读写的数据竞争风险，请务必遵守契约。

---

## Examples

仓库提供两个示例工程（`Examples/`，均不进入库分发产物）：

### BasicExample（git 追踪）

`Examples/BasicExample/`：通用门控范式演示。

- 经典 AppDelegate 生命周期（无 SceneDelegate），本地 SPM 包引用仓库根 `../../`；
- 首页展示“本次启动已执行的启动任务”清单（安全模式下不会构建）；
- “模拟启动闪退”按钮（DEBUG `fatalError`，连续 3 次重启后触发安全模式）；
- “模拟连续启动闪退”开关（DEBUG）：开启后每次启动约 1 秒自动崩溃并递减剩余
  次数，连续自动崩溃达到闪退阈值后，下次启动由安全模式菜单页接管，修复完成
  可经“重启应用”按钮一键重启——无需逐次手动点击，一键演示完整闭环。冒烟
  也可免 UI 直注入：
  `xcrun simctl spawn <udid> defaults write <bundleid> BasicExample.autoCrashRemaining -int 3`；
- “直接进入安全模式”调试入口（DEBUG `enterSafeModeForTesting()`）；
- 注册内置清缓存 + 自定义清理沙盒示例目录动作。

```bash
xcodebuild -project Examples/BasicExample/BasicExample.xcodeproj \
  -scheme BasicExample -destination 'generic/platform=iOS Simulator' build
```

### MPLaunchExample（本地专属，不入 git）

`Examples/MPLaunchExample/`：ALLaunchGuard × MPLaunch 编排门控全链路演示
（3 个 Launchable 模块依赖链、root VC 构建在模块 sceneDelegate 中）。

因依赖内部私有库 MPLaunch，该目录被 `.gitignore` 整目录忽略，仅存于本地。
若本机存在 `../mplaunch` 仓库，可从零搭建同类示例：

1. 新建 iOS App 工程（AppDelegate + SceneDelegate + Info.plist scene 配置）；
2. 添加两个本地包：仓库根 ALLaunchGuard 包 + mplaunch 包
   （**File → Add Package Dependencies… → Add Local…**）；
3. 按上文"MPLaunch 集成"代码编写 AppDelegate / SceneDelegate 门控；
4. 定义若干 `Launchable` 模块 + `extension Launchers` 的 `@objc` 属性注册 +
   `LaunchDependancyInjector` 依赖声明（参考 [MPLaunch](https://github.com/DaweiTang/MPLaunch) 用法）。

本地示例目录内附 `LOCAL_README.md`（双本地包引用说明）。

---

## Migration to 2.0

从 1.x 升级到 2.0.0 的破坏性变化与迁移指引：

> **升级首启注意**：若 1.x 存储中残留的 `consecutiveCrashCount` 已达阈值
>（或恰好差 1），升级到 2.0 后**首次启动即可能进入安全模式**（2.0 的
> `start()` 会预支递增计数）——残留计数代表此前已检测到的闪退循环，
> 属预期防护行为。因此升级时**必须至少注册一个 fixAction**；若
> `fixActions` 为空列表，库会自动提供内置“重置安全模式”动作兜底
>（见上文 FixAction 章节），不会出现无出口的困局。

### 1. `fixButtonTitle` 已移除 → `restartHint`

```swift
// 1.x
config.fixButtonTitle = "修复"

// 2.0：旧单按钮页已移除，改为菜单式修复页；
// 原 fixButtonTitle 的"引导修复"语义迁移为底部常驻重启提示
config.restartHint = "修复完成后，请退出应用重新打开"
```

### 2. 旧版单按钮安全模式页已移除

- `ALLaunchGuardViewController` 与 `presentSafeModeUIIfNeeded(fixHandler:)`
  已在 2.0 **移除**（不再以 deprecated 形式保留，引用将直接编译失败）。
  安全模式 UI 统一为菜单式的 `ALLaunchGuardSafeModeViewController`：
  由 `presentationStyle` 控制自动展示（`.dedicatedWindow` 独立窗口接管 /
  `.presentOnRoot` 在宿主 rootVC 上 present），宿主也可手动调用
  `activateSafeModeWindow()` 或 `presentSafeModeMenu()`。
- 原 `fixHandler` 清理逻辑迁移为注册 `ALLaunchGuardFixAction`
  （一行包装示例；`fixActions` 为空时库自动提供内置"重置安全模式"
  兑底动作，不会出现无出口困局）：

```swift
// 1.x：旧页 fixHandler 承担清理逻辑
// oldViewController.fixHandler = { clearCaches() }

// 2.0：注册为菜单修复动作（ALLaunchGuardClosureAction 一行包装）
ALLaunchGuard.shared.fixActions = [
    ALLaunchGuardClosureAction(title: "清理缓存") { completion in
        clearCaches()
        completion(true)
    }
]
```

### 3. 默认展示行为改为独立 UIWindow 接管

1.x 默认在 key window rootVC 上 present；2.0 默认 `.dedicatedWindow`
（独立 UIWindow 接管）。需要旧行为的宿主显式配置：

```swift
ALLaunchGuard.shared.uiConfig.presentationStyle = .presentOnRoot
```

注意 `.presentOnRoot` **仅回退挂载方式**（在宿主 key window rootVC 上
present，要求宿主已构建自身界面）——展示的页面仍是 2.0 菜单式
`ALLaunchGuardSafeModeViewController`，而不是 1.x 单按钮页；依赖 1.x
`fixHandler` 清理逻辑的宿主必须按第 5 节迁移为 `ALLaunchGuardFixAction`。

### 4. `start()` 返回值成为门控核心 + 5 秒自动清零语义

- 1.x：`start()` 仅为 Void 启动，宿主自行判断；2.0：`start()` 返回
  `Bool`，返回 `true` 时**必须跳过全部启动任务**（门控范式见 Quick Start）。
- 1.x 依赖宿主手动调用 `markLaunchSuccessful()` 清零计数；2.0 默认
  **存活满 5 秒（`survivalTimeout`）自动清零**，`markLaunchSuccessful()`
  保留（幂等共存），仅在需要提前确认时调用。
- `markLaunchSuccessful()` 仅作计数确认，**不退出安全模式**——安全模式
  启动下存活计时不会启动，此时调用不产生退出效果；安全模式唯一退出
  路径是修复动作成功（自动 `reset()`）或手动调用 `reset()`。
- 计数清零条件扩展：进入过后台死亡 / 设备重启 / 正常终止均不再误判为闪退。

### 5. 修复模式从"单按钮"升级为"菜单编排"

1.x 的单个 Fix 按钮 → 2.0 的 `fixActions` 菜单列表 +
`perform(_:completion:)` 统一编排（成功自动 reset、失败可重试）。
原 `fixHandler` 清理逻辑迁移为自定义 `ALLaunchGuardFixAction`。

---

## License

ALLaunchGuard 以 MIT 许可发布，详见 [LICENSE](LICENSE)。
