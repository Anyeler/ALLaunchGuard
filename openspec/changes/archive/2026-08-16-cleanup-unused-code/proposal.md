# 提案：cleanup-unused-code

## Why

死代码审计结论：真死代码极少（约 11 行），可简化约 85 行（结构简化 + 重复注释压缩 + 测试精简）。2.1 前四个变更（钩子/动作/并发加固）已合入，部分审计点位已随锁改造变化，需按当前代码状态重新核对后清理，使代码更简洁、逻辑更清晰（用户明确要求）。

## What Changes（纯清理，无行为变化，skip_specs）

- 删除：Examples/BasicExample 的 CrashSimulator.disarmIfFinished()（零调用）；ALLaunchGuardConfig 的 ALPlaceholderColor.label/secondaryLabel/systemBackground（所有编译配置下不可达，保留 systemOrange 与 init）。
- 简化：start() 内后台死亡/设备重启两处清零合并为一个条件（在锁改造后的新结构上核对位置）；survivalScheduler 声明处被 init 覆盖的无意义默认值去除（若锁改造后仍存在该形态）；VC 快照语义三连注释合一、窗口协调器 willConnect 保留 rationale 重复处压缩至类文档+分支①两处（保留 design 索引追溯）。
- 测试精简：重叠用例合并（testSuccessfulLaunchResetsCrashCounter 并入幂等/阈值测试）；testAutoPresentFalseDoesNotChangeGuardBehaviour 缩减为 setter 冒烟；MockDelegate 双状态合一（若仍存在）。
- 顺带：README 残留错别字修正（如"兑底动作"）。
- **明确不做**（与并发加固冲突或属防御性保留）：uiConfig 计算属性改直接存储（现承载锁存取器，保留）；协调器分支①/fallback 门控/VC 越界保护/guard didStart/MountDecision 决策纯函数（防御性保留）；presentSafeModeMenu 与协调器的 scene 遍历近似重复（语义不同，不动）。

## Capabilities

（skip_specs：纯重构清理，无 spec 级行为变化。）

## Impact

- Sources/（注释压缩与微简化）、Tests/（精简约 22 行）、Examples/BasicExample（删 1 方法）、README（错别字）。预计净减约 80-90 行。
- 验证：swift test 65 全绿 + iOS 构建 0 警告（注释压缩可能触碰 UIKit 分支）。
