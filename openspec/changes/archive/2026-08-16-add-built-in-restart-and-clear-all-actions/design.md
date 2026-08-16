# 设计：add-built-in-restart-and-clear-all-actions

## Context

现有内置动作：ALLaunchGuardClearCacheAction（仅 Caches，internal init(cachesDirectory:) 注入先例）、ALLaunchGuardResetSafeModeAction（空列表兜底）、ALLaunchGuardClosureAction。菜单页已有重启按钮（成功后展示、Alert 确认、exit(0)、allowRestartExit 开关）。编排层 perform 主队列收口 reset/delegate/completion。

## Goals / Non-Goals

**Goals:** 两个纯新增内置动作；重启 FIFO 时序正确性有测试锚定；全清白名单 TOCTOU 安全、失败聚合；零破坏。

**Non-Goals:** 自动排序/自动注入末位（注册顺序约定）；替换既有重启按钮；清缓存取消语义（演进项）；Library 内 Caches 之外的子目录清理（风险不可控）。

## Decisions

### D1. RestartAction 时序（load-bearing）
```swift
public func perform(completion: @escaping (Bool) -> Void) {
    completion(true)                                  // 编排层 reset 先入主队列
    DispatchQueue.main.async { self.exitHandler() }   // 晚一拍入队
}
internal var exitHandler: () -> Void = { exit(0) }
```
主队列 FIFO 保证编排层的 `DispatchQueue.main.async { reset() ... }` 先执行。测试注入 exitHandler 记录调用，断言"reset 效果（storage 清零）先于 exitHandler 被调"。图标 arrow.clockwise、isDestructive true。

### D2. ClearAllCacheAction 清理模型
- 顶层枚举 sandboxRoot（默认 NSHomeDirectory()，init(sandboxRoot:protectedTopLevelItems:) 可注入）：
  - 保护名单内（默认 Documents/Library/SystemData）：不删目录本身；Library 特殊处理——进入清理其 Caches 子目录内容。
  - tmp / .Trash：清空内容（目录保留）。
  - 其余游离顶层项：整个删除。
- 白名单判定在删除循环内逐条评估（传入当前条目名对照 protectedTopLevelItems），不用预过滤快照——TOCTOU 安全。
- FileManager.fileExists 不存在 → 跳过按成功；removeItem 抛错 → 记录 failed=true 继续；遍历完聚合 completion(!failed)。
- DispatchQueue.global(qos: .utility)，逐项 autoreleasepool。
- 元数据：title"深度清理缓存"（与 ClearCache 的"清理缓存"区分）、icon "trash.slash"、isDestructive true。

### D3. 与既有动作的关系
ClearCacheAction 保留（轻档位）；ClearAllCache 为深档位独立类；README 用表格说明两者范围差异与选择建议。重启按钮保留（UI 层能力，审核开关独立），动作与按钮可并存（宿主二选一或同用）。

## Risks / Trade-offs

- [误删宿主自建顶层目录] → 默认白名单保守 + protectedTopLevelItems 可扩展 + README 清理范围表 + 注入测试覆盖游离项场景。
- [FIFO 假设被未来编排层改动破坏] → load-bearing 注释 + 测试锚定。
- [Library/Caches 清理与 ClearCacheAction 重复] → 文档说明档位差异，宿主按需注册其一。
- [exit(0) 审核争议] → 动作由宿主显式注册（非默认行为），README 沿用既有审核风险说明。

## Migration Plan

实现 → 测试 → 归档。纯增量无迁移。

## Open Questions

（无。）
