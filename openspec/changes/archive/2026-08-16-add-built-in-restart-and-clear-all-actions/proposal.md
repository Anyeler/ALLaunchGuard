# 提案：add-built-in-restart-and-clear-all-actions

## Why

用户需求：安全模式内置通用修复动作——a) 重启 APP（放菜单最后）；b) 缓存全清（删除沙盒中所有非重要目录，内置目录白名单保护）。现有内置动作仅有清 Caches（ClearCacheAction）与空列表兜底重置（ResetSafeModeAction），缺少一键重启与白名单式深度清理能力。

## What Changes

- 新增 `ALLaunchGuardRestartAction`：title"重启应用"、icon "arrow.clockwise"、isDestructive true；perform 先 completion(true)（编排层 reset 入主队列）再主队列晚一拍 exit(0)，主队列 FIFO 保证 reset（清粘滞标记）先于进程终止；exitHandler internal 可注入测试。菜单末位由宿主按注册顺序约定（README 指引），库不做自动排序/注入。既有重启按钮保留（allowRestartExit 审核开关不受影响）。
- 新增 `ALLaunchGuardClearAllCacheAction`：白名单式沙盒全清。默认保护顶层目录 Documents/Library/SystemData（protectedTopLevelItems 可扩展）；清理 tmp 内容、.Trash、其余游离顶层项与 Library/Caches 内容；白名单在删除循环内逐条评估（消除枚举快照与删除之间的 TOCTOU）；条目已消失按成功幂等；单项失败继续清理其余项、最终聚合 completion(false)；DispatchQueue.global(qos: .utility) + autoreleasepool；internal init(sandboxRoot:) 注入测试。与 ClearCacheAction 共存（不同风险档位的独立动作）。
- README：内置动作清单、全清范围表、重启动作末位注册指引、与既有重启按钮的关系。

## Capabilities

### New Capabilities

（无新能力域。）

### Modified Capabilities

- `fix-actions`：ADDED"内置重启动作"与"内置白名单缓存全清动作"两条需求。

## Impact

- `Sources/ALLaunchGuard/ALLaunchGuardFixAction.swift`（追加两个类，纯新增零破坏）；`Tests/ALLaunchGuardTests/ALLaunchGuardFixActionTests.swift`（新增用例）；`README.md`。
- 误删防护：白名单默认保守 + 可扩展 + 注入测试；README 明示清理范围。
