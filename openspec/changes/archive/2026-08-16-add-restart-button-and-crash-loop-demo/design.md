# 设计：add-restart-button-and-crash-loop-demo

## Context

菜单页（ALLaunchGuardSafeModeViewController）底部现有常驻 restartHint UILabel，任一动作成功后 emphasize；修复成功后安全模式已退出（reset），此时进程内一切启动任务均未执行，唯一正确出路是冷启动——微信式"提示手动重启"，用户要求补一键重启。BasicExample 现有单次闪退按钮需手动循环，用户要求一键连续闪退演示。约束：iOS 14 安全 API；示例逻辑仅 DEBUG。

## Goals / Non-Goals

**Goals:** 修复成功后一键重启（二次确认 + exit(0)，可配置关闭）；Example 连续闪退闭环演示；测试与冒烟复验。

**Non-Goals:** 宿主自定义重启行为回调（delegate 拦截可后续按需加，Alert 确认已是清晰锚点）；热重启（iOS 不存在真正热重启，业界均为终止进程）；MPLaunchExample 改动（其现有闪退链路已可演示）。

## Decisions

### D1. 重启按钮形态：底部提示条右侧按钮 + Alert 二次确认 + exit(0)
底部区域改为水平布局（提示 Label + "重启应用" UIButton(type:.system)）；按钮初始隐藏，任一动作 success 后且 `config.allowRestartExit == true` 时展示（tintColor 强调）。点击 → UIAlertController(alert) "确认重启" → 确认 action 调 `exit(0)`。按钮用 iOS 14 安全 API（系统 UIButton + layer.cornerRadius）。
备选（无确认直接 exit）被否决：误触即杀进程，二次确认成本极低。

### D2. 默认开启但可关（allowRestartExit 默认 true）
用户明确要求该能力，默认开启；审核敏感宿主置 false 回退纯提示。README 注明 exit(0) 与 App Store 审核的已知争议（多数大厂安全模式均有"重启"按钮先例，风险低但保留开关）。

### D3. Example 自动崩溃演示：UserDefaults 计数 + 启动后 1 秒崩溃 + 进入安全模式即清零
`BasicExampleCrashSimulator`（示例内小类，#if DEBUG）：`remainingAutoCrashes`（Int，UserDefaults key "BasicExample.autoCrashRemaining"）；首页开关 UISwitch 开启 → 置 3 并持久化；AppDelegate didFinishLaunching（在 ALLaunchGuard.start() 正常门控之后、正常路径内）调用 `simulator.scheduleAutoCrashIfEnabled()`：若剩余 > 0 → 递减持久化 → DispatchQueue.main.asyncAfter(1.0) fatalError（处于 5 秒存活窗口内，计数保留）。崩溃前的递减必须先行持久化（fatalError 无 unwind）。开关状态绑定 remaining > 0（回首页自动回弹）。
**收尾修订（冒烟实测后决策）**：库为预支递增计数——达到阈值的那次启动 `start()` 直接返回 true 进入安全模式，不消耗 remaining；初版"3 次自动崩溃 → 第 4 次启动进安全模式"的表述与实现不符（默认阈值 3 实际为前两次启动自动崩溃、第三次启动接管，remaining 卡 1，修复重启后还会多崩一次）。最终决策：AppDelegate 安全模式路径（start() 返回 true 分支）#if DEBUG 调 `disarm()` 清零 remaining——进入安全模式即结束演示，修复重启后完全恢复；清零与 arm 值、阈值解耦，适配任意 crashThreshold。开关文案与 spec/proposal/tasks 同步改为预支递增语义描述。

### D4. 时机细节：崩溃调度放在正常启动路径内
若本次启动已进入安全模式（start() 返回 true），不调度自动崩溃（安全模式启动不打点不计时，崩溃无意义）；仅正常路径调度。1 秒延迟保证崩溃发生在存活窗口内且 UI 可见（用户能看到崩溃发生）。

## Risks / Trade-offs

- [exit(0) 审核争议] → 默认开 + 可配置关 + README 说明；业界安全模式先例（微信"重启微信"）。
- [自动崩溃演示留在 Release] → 整个 CrashSimulator 与开关 #if DEBUG 包裹，Release 示例不可见。
- [自动崩溃被 5 秒存活清零] → 1 秒 < survivalTimeout 5 秒，必然处于窗口内；冒烟验证默认阈值 3 下第三次启动进安全模式且演示剩余次数自动清零。

## Migration Plan

实现 → swift test（Config 新字段）→ xcodebuild iOS 构建 → BasicExample 冒烟（开关 → 前两次自动崩溃 → 第三次启动安全模式并自动清零 → 修复 → 重启按钮 → 恢复）→ 归档。

## Open Questions

（无。）
