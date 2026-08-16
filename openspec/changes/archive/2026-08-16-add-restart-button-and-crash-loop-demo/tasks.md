# 任务：add-restart-button-and-crash-loop-demo

## 1. 库：重启按钮（TDD：先写失败测试）

- [x] 1.1 先写测试：Config 新字段 `restartButtonTitle: String`（默认“重启应用”）与 `allowRestartExit: Bool`（默认 true）的默认值/自定义值断言（testConfigDefaultValues / testConfigCustomValues 补充）
- [x] 1.2 `Sources/ALLaunchGuard/ALLaunchGuardConfig.swift`：新增两字段与 init 参数（带默认值，源码兼容）
- [x] 1.3 `Sources/ALLaunchGuard/ALLaunchGuardSafeModeViewController.swift`：底部改为提示 Label + 隐藏的“重启应用”按钮（UIButton(type:.system) + cornerRadius，iOS 14 安全 API）；任一动作 success 且 `config.allowRestartExit == true` 时展示；点击 → UIAlertController 二次确认（标题“重启应用”、确认 action 调 `exit(0)`）；未修复成功前按钮不展示；`allowRestartExit == false` 恒不展示

## 2. BasicExample：连续闪退演示

- [x] 2.1 新增 `Examples/BasicExample/BasicExample/CrashSimulator.swift`（#if DEBUG）：remainingAutoCrashes 持久化（UserDefaults key "BasicExample.autoCrashRemaining"）；`arm()`（置 3）、`scheduleAutoCrashIfEnabled()`（剩余 > 0 → 先递减持久化 → main.asyncAfter 1 秒 fatalError）、`disarmIfFinished()`、状态查询
- [x] 2.2 `AppDelegate.swift`：正常启动路径（start() 返回 false 分支）内 #if DEBUG 调 scheduleAutoCrashIfEnabled()；安全模式路径不调度
- [x] 2.3 `HomeViewController.swift`：#if DEBUG 增加"模拟连续启动闪退"UISwitch（状态绑定 remaining > 0；开启调 arm()，关闭清零；收尾后标题不带写死次数，文案适配任意阈值）；保留既有按钮；页面增加说明文案（达到闪退阈值后下次启动进入安全模式并自动结束演示）

## 3. 验证

- [x] 3.1 swift test 全绿（50 存量 + Config 新增断言）；swift build 0 新增警告
- [x] 3.2 xcodebuild -scheme ALLaunchGuard iOS Simulator 构建（独立 derivedDataPath）0 错误 0 警告；BasicExample 构建 BUILD SUCCEEDED
- [x] 3.3 BasicExample 冒烟闭环（simctl + 模拟器，截图存 /tmp 新路径）：开启开关（可用 simctl spawn defaults 写入 remaining=3 替代 UI 点击）→ launch → 1 秒内崩溃 → 重复自动崩溃至达到闪退阈值 → 安全模式菜单页接管截图 → （修复点击如无法自动化，验证菜单页与重启按钮存在即可并说明）→ 确认开关归零
  - 实测说明：默认阈值 3（预支递增、第 3 次启动即触发）下实际为 2 次自动崩溃 → 第 3 次启动安全模式接管；修复 + 重启按钮闭环经 computer-use 实点验证全通（截图 /tmp/alguard-restart-*）；remaining 需读 app 沙盒 plist（simctl spawn defaults 域不同步）
- [x] 3.4 README：配置表补 restartButtonTitle / allowRestartExit；补 exit(0) 审核风险与开关说明；Examples 指引补连续闪退演示用法

## 4. 收尾：预支计数语义对齐（决策：进入安全模式即自动清零，适配任意阈值）

- [x] 4.1 `AppDelegate.swift`：安全模式路径（`ALLaunchGuard.shared.start()` 返回 true 分支）#if DEBUG 调 `BasicExampleCrashSimulator.shared.disarm()` 清零 remaining（持久化 0）——进入安全模式即结束演示，避免残留导致修复重启后再多崩一次；与阈值解耦，任意 crashThreshold 下行为一致
- [x] 4.2 `HomeViewController.swift`：开关标题去掉写死"3 次"；说明文案改为适配任意阈值的准确描述（"接下来几次启动将在存活窗口内自动崩溃；达到闪退阈值（默认 3）后下次启动进入安全模式并自动结束演示"）；手动闪退按钮标题同步去掉写死次数；`CrashSimulator.swift` 注释与崩溃日志改为预支递增语义（去掉硬编码编号 3）
- [x] 4.3 spec（example-apps：requirement、"崩溃循环"与"一键连续闪退演示"两场景）、proposal.md、design.md（D3 收尾修订 + Risks + Migration Plan）、tasks.md 中"3 次自动崩溃 / 第 4 次启动"等写死表述修正为预支递增语义准确描述（默认阈值 3：前两次启动自动崩溃、第三次启动进入安全模式并自动清零；修复并一键重启后完全恢复）
- [x] 4.4 验证：swift test 50 全绿；BasicExample 构建 BUILD SUCCEEDED（独立 derivedDataPath）；simctl 冒烟复验（boot 模拟器 → 安装 → 注入 remaining=3 → launch 两次均崩溃 → 第三次 launch 安全模式接管（截图 /tmp/alguard-demo-fix-*）→ 沙盒 plist 确认 BasicExample.autoCrashRemaining 已为 0）→ uninstall 清理；修复 + 重启按钮实点链路沿用上一轮验证结论（/tmp/alguard-restart-*）
