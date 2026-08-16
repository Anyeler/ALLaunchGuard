# 提案：add-restart-button-and-crash-loop-demo

## Why

用户提出两点完善：① Example 需要真正"连续启动闪退"的演示——现有的"模拟启动闪退"按钮每次需手动重开 App 再点一次，无法一键演示崩溃循环触发安全模式的完整链路；② 修复动作成功后菜单页只有文字提示"请退出应用重新打开"，缺少一键"重启应用"按钮（终止进程，下次冷启动恢复正常流程），修复闭环体验不完整。

## What Changes

- **安全模式菜单页（库）**：任一修复动作成功后，底部在重启提示旁展示"重启应用"按钮；点击后终止进程（`exit(0)`）。新增配置：`restartButtonTitle`（默认"重启应用"）、`allowRestartExit: Bool`（默认 true；置 false 时按钮隐藏，保留纯提示旧行为，供审核敏感宿主选择）。按钮触发前弹系统 Alert 二次确认（避免误触，且为宿主提供可替换行为的清晰锚点）。README 同步说明 exit(0) 的审核风险与开关。
- **BasicExample（示例）**：首页新增"模拟连续启动闪退"开关（UserDefaults 持久化）：开启后记录剩余自动崩溃次数为 3；正常启动路径若剩余次数 > 0，则在约 1 秒后（5 秒存活窗口内）自动 fatalError 崩溃并递减计数；达到闪退阈值的那次启动直接进入安全模式（库为预支递增计数，默认阈值 3：前两次启动自动崩溃、第三次启动接管），并在安全模式路径自动清零剩余次数——修复重启后完全恢复，完整演示"连续闪退 → 安全模式接管 → 修复 → 重启按钮 → 恢复"闭环（适配任意阈值）。保留现有单次"模拟启动闪退"按钮与 DEBUG 直进入入口。

## Capabilities

### New Capabilities

（无。）

### Modified Capabilities

- `safe-mode-ui`：重启提示需求扩展——修复成功后提供可配置的"重启应用"按钮（二次确认 + 进程终止 + 开关与文案配置）。
- `example-apps`：通用示例 App 需求扩展——提供连续启动闪退自动崩溃演示开关（达到闪退阈值的那次启动进入安全模式并自动清零，适配任意阈值，默认阈值 3 下为前两次自动崩溃、第三次启动接管闭环）。

## Impact

- 库：`Sources/ALLaunchGuard/ALLaunchGuardSafeModeViewController.swift`（按钮 + Alert + exit）、`Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`（两个新配置字段，带默认值源码兼容）。
- 示例：`Examples/BasicExample/BasicExample/HomeViewController.swift`（开关）+ `AppDelegate.swift`（启动时自动崩溃逻辑）+ 可能新增小工具类。
- 测试：Config 新字段默认值/自定义测试；README 配置表与审核风险说明更新；冒烟复验闭环。
